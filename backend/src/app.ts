import { ApiError, errorResponse, int, json, oneOf, optionalStr, readJson, str, stringList } from "./http";
import { authenticate, registerDevice, type Device } from "./auth";
import { hit } from "./ratelimit";
import {
  applySubscription, entitlementOf, grantPromo, reserve, settle, status, units,
  type Entitlement,
} from "./quota";
import { redeem } from "./promo";
import { verifySubscription } from "./appstore";
import { episodeFacts } from "./tvmaze";
import { catalogNotes, listShows, localizeNotes, showDecks } from "./catalog";
import {
  DECK_MAX_TOKENS, DECK_SCHEMA, DISCUSSION_MAX_TOKENS, DISCUSSION_SCHEMA, KNOWN_TERMS_LIMIT,
  LANGUAGES, LEVELS, MAX_LEARNER_TURNS, deckFile, deckSystem, deckUserMessage,
  discussionMessages, discussionSystem, estimateTokens, parseDeckNotes, parseDiscussionReply,
  type Turn,
} from "./prompts";
import { PaidModelError, type ClaudeCall } from "./claude";
import { hmacHex } from "./crypto";
import { intVar, type Deps, type Env } from "./env";

/** Субтитры одной серии — 30–60 тысяч символов; больше — это сезон. */
const SUBTITLES_LIMIT = 200_000;
const BODY_LIMIT = 300_000;

/**
 * Все маршруты API. Любая ошибка превращается в код для клиента; всё
 * непредвиденное — в «internal» без подробностей.
 */
export async function handle(request: Request, env: Env, deps: Deps): Promise<Response> {
  try {
    const url = new URL(request.url);
    const route = `${request.method} ${url.pathname}`;
    switch (route) {
      case "POST /v1/devices": return await register(request, env, deps);
      case "GET /v1/me": return await me(request, env, deps);
      case "DELETE /v1/me": return await forget(request, env, deps);
      case "POST /v1/promo/redeem": return await redeemPromo(request, env, deps);
      case "POST /v1/subscription/verify": return await verify(request, env, deps);
      case "POST /v1/deck": return await deck(request, env, deps);
      case "POST /v1/discuss": return await discuss(request, env, deps);
      case "GET /v1/catalog": return await catalog(request, env, deps);
    }
    const show = /^\/v1\/catalog\/(\d{1,8})$/.exec(url.pathname);
    if (request.method === "GET" && show?.[1]) {
      return await catalogShow(request, env, deps, Number(show[1]));
    }
    throw new ApiError(404, "not_found");
  } catch (error) {
    if (error instanceof ApiError) return errorResponse(error);
    console.error("unexpected", error instanceof Error ? error.name : "unknown");
    return errorResponse(new ApiError(500, "internal"));
  }
}

// MARK: - Устройство и доступ

async function register(request: Request, env: Env, deps: Deps): Promise<Response> {
  // IP хранится только как HMAC — сам адрес в базе не оседает.
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  await hit(env.DB, "reg:" + await hmacHex(env.PROMO_PEPPER, ip), 20, 3600, deps.now());
  const token = await registerDevice(env.DB, deps);
  return json({ token }, 201);
}

async function context(request: Request, env: Env, deps: Deps) {
  const device = await authenticate(request, env.DB, deps);
  const entitlement = await entitlementOf(env.DB, device.entitlement_id, deps.now());
  return { device, entitlement };
}

async function me(request: Request, env: Env, deps: Deps): Promise<Response> {
  const { entitlement } = await context(request, env, deps);
  return json(status(entitlement, deps.now()));
}

/**
 * «Удалить все данные» в приложении: стираются устройство, его серии и
 * расход. Промо-доступ, которым больше никто не пользуется, — тоже.
 * Подписка остаётся: она принадлежит покупке в App Store, а не телефону,
 * и вернётся на новом устройстве через «Восстановить покупки».
 */
async function forget(request: Request, env: Env, deps: Deps): Promise<Response> {
  const { device, entitlement } = await context(request, env, deps);
  const statements = [
    env.DB.prepare("DELETE FROM device_episodes WHERE device_id = ?").bind(device.id),
    env.DB.prepare("DELETE FROM usage_log WHERE device_id = ?").bind(device.id),
    env.DB.prepare("DELETE FROM devices WHERE id = ?").bind(device.id),
  ];
  if (entitlement?.kind === "promo") {
    statements.push(env.DB.prepare(
      `DELETE FROM entitlements WHERE id = ?
       AND NOT EXISTS (SELECT 1 FROM devices WHERE entitlement_id = ? AND id != ?)`,
    ).bind(entitlement.id, entitlement.id, device.id));
    statements.push(env.DB.prepare(
      "UPDATE promo_codes SET redeemed_by = NULL WHERE redeemed_by = ?").bind(device.id));
  }
  await env.DB.batch(statements);
  return json({ deleted: true });
}

async function redeemPromo(request: Request, env: Env, deps: Deps): Promise<Response> {
  const { device, entitlement } = await context(request, env, deps);
  const now = deps.now();
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  // Перебор бесполезен и так (80 бит), но попытки всё равно ограничены.
  await hit(env.DB, "redeem:" + device.id, 5, 3600, now);
  await hit(env.DB, "redeem-ip:" + await hmacHex(env.PROMO_PEPPER, ip), 20, 3600, now);
  const body = await readJson(request, 1_000);
  const grant = await redeem(env.DB, env.PROMO_PEPPER, str(body, "code", 64), device.id, now);
  await grantPromo(env.DB, deps, device.id, entitlement, grant.days,
    grant.units || intVar(env.PROMO_UNITS, 2_000_000));
  const refreshed = await context(request, env, deps);
  return json(status(refreshed.entitlement, now));
}

async function verify(request: Request, env: Env, deps: Deps): Promise<Response> {
  const { device } = await context(request, env, deps);
  await hit(env.DB, "verify:" + device.id, 10, 3600, deps.now());
  const body = await readJson(request, 1_000);
  const subscription = await verifySubscription(env, deps, str(body, "transactionId", 32));
  await applySubscription(env.DB, deps, device.id, subscription,
    intVar(env.SUBSCRIPTION_UNITS, 2_000_000), intVar(env.MAX_DEVICES_PER_SUBSCRIPTION, 3));
  const refreshed = await context(request, env, deps);
  return json(status(refreshed.entitlement, deps.now()));
}

// MARK: - ИИ

/** Доступ есть и не истёк — иначе 402 с понятным кодом. */
function requireActive(entitlement: Entitlement | null, now: number): Entitlement {
  if (!entitlement) throw new ApiError(402, "no_plan");
  if (entitlement.period_end <= now) throw new ApiError(402, "plan_expired");
  return entitlement;
}

async function limitAI(env: Env, device: Device, now: number) {
  await hit(env.DB, "ai-min:" + device.id, 6, 60, now);
  await hit(env.DB, "ai-day:" + device.id, 150, 86_400, now);
}

/**
 * Запрос к модели с бронью: сначала единицы бронируются по худшему случаю,
 * после ответа списывается фактический расход. Упал запрос до ответа —
 * бронь просто снимается.
 */
async function callWithQuota(
  env: Env, deps: Deps, device: Device, entitlement: Entitlement, kind: string, call: ClaudeCall,
) {
  const input = estimateTokens(call.system)
    + call.messages.reduce((sum, message) => sum + estimateTokens(message.content), 0);
  const reservationId = await reserve(env.DB, deps, entitlement.id, units(input, call.maxTokens));
  let spentIn = 0;
  let spentOut = 0;
  try {
    const result = await deps.claude.complete(call);
    spentIn = result.inputTokens;
    spentOut = result.outputTokens;
    return result;
  } catch (error) {
    if (error instanceof PaidModelError) {
      spentIn = error.inputTokens;
      spentOut = error.outputTokens;
    }
    throw error;
  } finally {
    const spent = units(spentIn, spentOut);
    await settle(env.DB, entitlement.id, reservationId, spent, deps.now());
    if (spent > 0) {
      await env.DB.prepare(
        `INSERT INTO usage_log (entitlement_id, device_id, kind, input_tokens, output_tokens,
           units, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`,
      ).bind(entitlement.id, device.id, kind, spentIn, spentOut, spent, deps.now()).run();
    }
  }
}

async function rememberEpisode(env: Env, deps: Deps, device: Device,
                               showId: number, season: number, episode: number) {
  await env.DB.prepare(
    `INSERT OR IGNORE INTO device_episodes (device_id, show_id, season, episode, created_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).bind(device.id, showId, season, episode, deps.now()).run();
}

async function deck(request: Request, env: Env, deps: Deps): Promise<Response> {
  const { device, entitlement } = await context(request, env, deps);
  const now = deps.now();
  const body = await readJson(request, BODY_LIMIT);
  const showId = int(body, "showId", 1, 99_999_999);
  const season = int(body, "season", 1, 99);
  const episode = int(body, "episode", 1, 999);
  const language = oneOf(body, "language", LANGUAGES)!;
  const level = oneOf(body, "level", LEVELS, true);
  const wordCount = int(body, "wordCount", 5, 40);
  const knownTerms = stringList(body, "knownTerms", KNOWN_TERMS_LIMIT, 80);
  const subtitles = optionalStr(body, "subtitles", SUBTITLES_LIMIT);

  // Каталог открыт и без подписки — но каждый запрос ходит в TVMaze,
  // поэтому и бесплатные запросы ограничены.
  await hit(env.DB, "deck:" + device.id, 30, 60, now);
  const facts = await episodeFacts(env.DB, deps, showId, season, episode);

  // Готовый набор из каталога — бесплатно и без подписки: модель уже
  // отработала один раз за всех, а сервер только читает базу.
  if (!subtitles) {
    const catalog = await catalogNotes(env.DB, showId, season, episode);
    if (catalog) {
      await rememberEpisode(env, deps, device, showId, season, episode);
      const notes = localizeNotes(catalog, language, knownTerms).slice(0, wordCount);
      return json({ deck: deckFile(facts, language, notes), source: "catalog",
                    plan: status(entitlement, now) });
    }
  }

  const active = requireActive(entitlement, now);
  await limitAI(env, device, now);
  const input = { facts, language, level, wordCount, knownTerms, subtitles };
  const result = await callWithQuota(env, deps, device, active, "deck", {
    system: deckSystem(input),
    messages: [{ role: "user", content: deckUserMessage(input) }],
    maxTokens: DECK_MAX_TOKENS,
    schema: DECK_SCHEMA as unknown as Record<string, unknown>,
  });
  const notes = parseDeckNotes(result.text, wordCount);
  if (notes.length === 0) throw new ApiError(502, "model_error");
  await rememberEpisode(env, deps, device, showId, season, episode);
  return json({ deck: deckFile(facts, language, notes), source: "model",
                plan: status(await entitlementOf(env.DB, active.id, deps.now()), deps.now()) });
}

async function discuss(request: Request, env: Env, deps: Deps): Promise<Response> {
  const { device, entitlement } = await context(request, env, deps);
  const now = deps.now();
  const active = requireActive(entitlement, now);
  const body = await readJson(request, 60_000);
  const showId = int(body, "showId", 1, 99_999_999);
  const season = int(body, "season", 1, 99);
  const episode = int(body, "episode", 1, 999);
  const language = oneOf(body, "language", LANGUAGES)!;
  const level = oneOf(body, "level", LEVELS, true);
  const retelling = optionalStr(body, "retelling", 4_000);
  const turns = parseTurns(body.turns);

  // Разговор — только о серии, к которой уже взяты слова: так подписка
  // тратится на изучение сериалов, а не на чат обо всём.
  const unlocked = await env.DB.prepare(
    `SELECT 1 AS ok FROM device_episodes
     WHERE device_id = ? AND show_id = ? AND season = ? AND episode = ?`,
  ).bind(device.id, showId, season, episode).first();
  if (!unlocked) throw new ApiError(403, "episode_locked");

  await limitAI(env, device, now);
  const facts = await episodeFacts(env.DB, deps, showId, season, episode);
  const result = await callWithQuota(env, deps, device, active, "discuss", {
    system: discussionSystem(facts, language, level, retelling),
    messages: discussionMessages(turns),
    maxTokens: DISCUSSION_MAX_TOKENS,
    schema: DISCUSSION_SCHEMA as unknown as Record<string, unknown>,
  });
  const reply = parseDiscussionReply(result.text);
  if (!reply) throw new ApiError(502, "model_error");
  return json({ ...reply, plan: status(await entitlementOf(env.DB, active.id, deps.now()), deps.now()) });
}

/** Реплики разговора: не больше шести ответов ученика, короткие тексты. */
function parseTurns(value: unknown): Turn[] {
  if (!Array.isArray(value) || value.length > MAX_LEARNER_TURNS * 2 + 1) {
    throw new ApiError(400, "invalid_field", "turns");
  }
  const turns = value.map((item): Turn => {
    const record = item as Record<string, unknown> | null;
    const speaker = record?.speaker;
    const text = record?.text;
    const limit = speaker === "learner" ? 600 : 1_200;
    if ((speaker !== "learner" && speaker !== "monchik")
        || typeof text !== "string" || text.length > limit) {
      throw new ApiError(400, "invalid_field", "turns");
    }
    return { speaker, text };
  });
  if (turns.filter((turn) => turn.speaker === "learner").length > MAX_LEARNER_TURNS) {
    throw new ApiError(400, "conversation_over");
  }
  return turns;
}

// MARK: - Каталог

async function catalog(request: Request, env: Env, deps: Deps): Promise<Response> {
  await authenticate(request, env.DB, deps);
  return json({ shows: await listShows(env.DB) });
}

async function catalogShow(request: Request, env: Env, deps: Deps, showId: number) {
  await authenticate(request, env.DB, deps);
  return json({ showId, decks: await showDecks(env.DB, showId) });
}
