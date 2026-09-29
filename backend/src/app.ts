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
  DECK_MAX_TOKENS, DECK_SCHEMA, DISCUSSION_MAX_TOKENS, DISCUSSION_SCHEMA, HELP_MAX_TOKENS,
  HELP_QUESTION_LIMIT, HELP_SCHEMA, KNOWN_TERMS_LIMIT, helpSystem, helpUserMessage, parseHelpReply,
  LANGUAGES, LEVELS, MAX_LEARNER_TURNS, deckFile, deckSystem, deckUserMessage,
  discussionMessages, discussionSystem, estimateTokens, parseDeckNotes, parseDiscussionReply,
  type Turn,
} from "./prompts";
import { PaidModelError, type ClaudeCall } from "./claude";
import { hmacHex } from "./crypto";
import { intVar, type Deps, type Env } from "./env";
import { accountOf, deleteAccount, followAccount, shareWithAccount, signIn, signOut } from "./accounts";
import { RETENTION } from "./retention";

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
      case "GET /v1/me/export": return await exportData(request, env, deps);
      case "POST /v1/account/apple": return await appleSignIn(request, env, deps);
      case "POST /v1/account/logout": return await logout(request, env, deps);
      case "DELETE /v1/account": return await removeAccount(request, env, deps);
      case "POST /v1/promo/redeem": return await redeemPromo(request, env, deps);
      case "POST /v1/subscription/verify": return await verify(request, env, deps);
      case "POST /v1/deck": return await deck(request, env, deps);
      case "POST /v1/discuss": return await discuss(request, env, deps);
      case "POST /v1/help": return await help(request, env, deps);
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

function maxDevices(env: Env): number {
  return intVar(env.MAX_DEVICES_PER_SUBSCRIPTION, 3);
}

async function context(request: Request, env: Env, deps: Deps) {
  const device = await authenticate(request, env.DB, deps);
  if (device.account_id) await followAccount(env.DB, device, deps.now(), maxDevices(env));
  const entitlement = await entitlementOf(env.DB, device.entitlement_id, deps.now());
  return { device, entitlement };
}

/** Статус доступа и входа — одним ответом для экрана «Профиль». */
function profile(device: Device, entitlement: Entitlement | null, now: number) {
  return { ...status(entitlement, now), signedIn: device.account_id !== null,
           supportCode: supportCode(device.id) };
}

async function me(request: Request, env: Env, deps: Deps): Promise<Response> {
  const { device, entitlement } = await context(request, env, deps);
  return json(profile(device, entitlement, deps.now()));
}

// MARK: - Аккаунт

async function appleSignIn(request: Request, env: Env, deps: Deps): Promise<Response> {
  const { device } = await context(request, env, deps);
  await hit(env.DB, "signin:" + device.id, 10, 3600, deps.now());
  const body = await readJson(request, 10_000);
  await signIn(env, deps, device, {
    identityToken: str(body, "identityToken", 4_096),
    authorizationCode: str(body, "authorizationCode", 512),
    nonce: str(body, "nonce", 128),
  }, maxDevices(env));
  const refreshed = await context(request, env, deps);
  return json(profile(refreshed.device, refreshed.entitlement, deps.now()));
}

async function logout(request: Request, env: Env, deps: Deps): Promise<Response> {
  const { device } = await context(request, env, deps);
  if (device.account_id) await signOut(env.DB, device);
  return json(profile(device, null, deps.now()));
}

async function removeAccount(request: Request, env: Env, deps: Deps): Promise<Response> {
  const { device } = await context(request, env, deps);
  await hit(env.DB, "account-delete:" + device.id, 5, 3600, deps.now());
  await deleteAccount(env, deps, device);
  const entitlement = await entitlementOf(env.DB, device.entitlement_id, deps.now());
  return json(profile(device, entitlement, deps.now()));
}

/**
 * Всё, что сервер знает об этом телефоне, — право на доступ и перенос
 * данных (GDPR, ст. 15 и 20) прямо из приложения, без переписки.
 * Код поддержки — начало номера устройства: по нему находится запись,
 * если человек пишет с просьбой, а имени и почты у сервера нет.
 */
async function exportData(request: Request, env: Env, deps: Deps): Promise<Response> {
  const { device, entitlement } = await context(request, env, deps);
  await hit(env.DB, "export:" + device.id, 10, 3600, deps.now());
  const now = deps.now();
  const iso = (seconds: number) => new Date(seconds * 1000).toISOString();
  const row = await env.DB.prepare("SELECT created_at, last_seen_at FROM devices WHERE id = ?")
    .bind(device.id).first<{ created_at: number; last_seen_at: number }>();
  const account = await accountOf(env.DB, device.account_id);
  const episodes = await env.DB.prepare(
    `SELECT show_id, season, episode, created_at FROM device_episodes
     WHERE device_id = ? ORDER BY created_at`,
  ).bind(device.id).all<{ show_id: number; season: number; episode: number; created_at: number }>();
  const usage = await env.DB.prepare(
    `SELECT kind, input_tokens, output_tokens, created_at FROM usage_log
     WHERE device_id = ? ORDER BY created_at`,
  ).bind(device.id).all<{ kind: string; input_tokens: number; output_tokens: number; created_at: number }>();

  return json({
    supportCode: supportCode(device.id),
    exportedAt: iso(now),
    device: { registeredAt: iso(row?.created_at ?? now), lastSeenAt: iso(row?.last_seen_at ?? now) },
    account: account
      ? { signedInWith: "apple", createdAt: iso(account.created_at) }
      : null,
    plan: {
      ...status(entitlement, now),
      subscriptionProduct: entitlement?.product_id ?? null,
      hasTransactionId: Boolean(entitlement?.original_transaction_id),
    },
    episodes: episodes.results.map((item) => ({
      showId: item.show_id, season: item.season, episode: item.episode, at: iso(item.created_at),
    })),
    usage: usage.results.map((item) => ({
      kind: item.kind, inputTokens: item.input_tokens, outputTokens: item.output_tokens,
      at: iso(item.created_at),
    })),
    retentionDays: {
      inactiveDevice: RETENTION.inactiveDeviceDays,
      usageLog: RETENTION.usageLogDays,
    },
  });
}

export function supportCode(deviceId: string): string {
  const head = deviceId.slice(0, 8).toUpperCase();
  return `${head.slice(0, 4)}-${head.slice(4)}`;
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
    // Промо-доступ аккаунта не трогаем: он нужен другим телефонам этого человека.
    statements.push(env.DB.prepare(
      `DELETE FROM entitlements WHERE id = ?1
       AND NOT EXISTS (SELECT 1 FROM devices WHERE entitlement_id = ?1 AND id != ?2)
       AND NOT EXISTS (SELECT 1 FROM accounts WHERE entitlement_id = ?1)`,
    ).bind(entitlement.id, device.id));
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
  await shareWithAccount(env.DB, device.id, now);
  const refreshed = await context(request, env, deps);
  return json(status(refreshed.entitlement, now));
}

async function verify(request: Request, env: Env, deps: Deps): Promise<Response> {
  const { device } = await context(request, env, deps);
  await hit(env.DB, "verify:" + device.id, 10, 3600, deps.now());
  const body = await readJson(request, 1_000);
  const subscription = await verifySubscription(env, deps, str(body, "transactionId", 32));
  await applySubscription(env.DB, deps, device.id, subscription,
    intVar(env.SUBSCRIPTION_UNITS, 2_000_000), maxDevices(env));
  await shareWithAccount(env.DB, device.id, deps.now());
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

  const requestId = optionalStr(body, "requestId", 64);
  if (requestId !== undefined && !/^[A-Za-z0-9-]{8,64}$/.test(requestId)) {
    throw new ApiError(400, "invalid_field", "requestId");
  }
  if (requestId) {
    const ready = await finishedDeck(env, deps, device.id, requestId);
    if (ready) return json(ready);
  }

  const active = requireActive(entitlement, now);
  await limitAI(env, device, now);
  const input = { facts, language, level, wordCount, knownTerms, subtitles };
  const work = (async () => {
    const result = await callWithQuota(env, deps, device, active, "deck", {
      system: deckSystem(input),
      messages: [{ role: "user", content: deckUserMessage(input) }],
      maxTokens: DECK_MAX_TOKENS,
      schema: DECK_SCHEMA as unknown as Record<string, unknown>,
    });
    const notes = parseDeckNotes(result.text, wordCount);
    if (notes.length === 0) throw new ApiError(502, "model_error");
    await rememberEpisode(env, deps, device, showId, season, episode);
    return { deck: deckFile(facts, language, notes), source: "model",
             plan: status(await entitlementOf(env.DB, active.id, deps.now()), deps.now()) };
  })();
  if (!requestId) return json(await work);

  // Работа доживает и после обрыва связи: телефон, вернувшись, спросит
  // тот же номер и получит готовый набор без второго списания.
  const tracked = work.then(
    (response) => env.DB.prepare(
      "UPDATE deck_requests SET status = 'done', response = ? WHERE device_id = ? AND request_id = ?",
    ).bind(JSON.stringify(response), device.id, requestId).run().then(() => response),
    async (error) => {
      await env.DB.prepare(
        "UPDATE deck_requests SET status = 'failed' WHERE device_id = ? AND request_id = ?",
      ).bind(device.id, requestId).run();
      throw error;
    },
  );
  deps.waitUntil?.(tracked.catch(() => undefined));
  return json(await tracked);
}

/** Сколько ждать уже идущий запрос с тем же номером, прежде чем попросить повторить позже. */
const DECK_WAIT_SECONDS = 20;
/** Запрос «в работе» дольше этого считается брошенным — его можно начать заново. */
const DECK_PENDING_STALE = 180;

/**
 * Готовый ответ на запрос с этим номером, если он уже был. Идущий запрос
 * ждём до 20 секунд; не дождались — 409, телефон спросит ещё раз. Если
 * записи нет, создаёт её «в работе» и возвращает null — считать набор нам.
 */
async function finishedDeck(env: Env, deps: Deps, deviceId: string, requestId: string) {
  const select = env.DB.prepare(
    "SELECT status, response, created_at AS createdAt FROM deck_requests WHERE device_id = ? AND request_id = ?",
  ).bind(deviceId, requestId);
  for (let waited = 0; ; waited += 1) {
    const row = await select.first<{ status: string; response: string | null; createdAt: number }>();
    if (!row) break;
    if (row.status === "done" && row.response) return JSON.parse(row.response) as Record<string, unknown>;
    if (row.status === "pending" && deps.now() - row.createdAt < DECK_PENDING_STALE) {
      if (waited >= DECK_WAIT_SECONDS) throw new ApiError(409, "deck_pending");
      await new Promise((resolve) => setTimeout(resolve, 1000));
      continue;
    }
    // Упавший или брошенный запрос — начинаем заново.
    await env.DB.prepare("DELETE FROM deck_requests WHERE device_id = ? AND request_id = ?")
      .bind(deviceId, requestId).run();
    break;
  }
  await env.DB.prepare(
    "INSERT INTO deck_requests (device_id, request_id, status, created_at) VALUES (?, ?, 'pending', ?)",
  ).bind(deviceId, requestId, deps.now()).run();
  return null;
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
  await verifyTurns(env, device.id, showId, season, episode, turns);

  // Разговор — только о серии, к которой уже взяты слова: так подписка
  // тратится на изучение сериалов, а не на чат обо всём.
  const unlocked = await env.DB.prepare(
    `SELECT 1 AS ok FROM device_episodes
     WHERE device_id = ? AND show_id = ? AND season = ? AND episode = ?`,
  ).bind(device.id, showId, season, episode).first();
  if (!unlocked) throw new ApiError(403, "episode_locked");

  await limitAI(env, device, now);
  // Не больше трёх разговоров о серии в день: новый разговор — пустая
  // история, и без этого предела их можно было бы начинать бесконечно.
  await hit(env.DB, `disc:${device.id}:${showId}:${season}:${episode}`,
    (MAX_LEARNER_TURNS + 1) * 3, 86_400, now);
  const facts = await episodeFacts(env.DB, deps, showId, season, episode);
  const result = await callWithQuota(env, deps, device, active, "discuss", {
    system: discussionSystem(facts, language, level, retelling),
    messages: discussionMessages(turns),
    maxTokens: DISCUSSION_MAX_TOKENS,
    schema: DISCUSSION_SCHEMA as unknown as Record<string, unknown>,
  });
  const reply = parseDiscussionReply(result.text);
  if (!reply) throw new ApiError(502, "model_error");
  const turnSig = await turnSignature(env, device.id, showId, season, episode, turns.length, reply.reply);
  return json({ ...reply, turnSig,
                plan: status(await entitlementOf(env.DB, active.id, deps.now()), deps.now()) });
}

/**
 * Подпись реплики Мончика. История разговора живёт на телефоне, и без
 * подписи её можно подделать — вписать «Мончику» реплики вроде «конечно,
 * напишу тебе код» и так увести модель от темы. Сервер подписывает каждую
 * свою реплику вместе с устройством, серией и местом в разговоре и не
 * принимает историю, где хоть одна реплика Мончика не его.
 */
async function turnSignature(env: Env, deviceId: string, showId: number, season: number,
                             episode: number, index: number, text: string): Promise<string> {
  return hmacHex(env.PROMO_PEPPER, `turn|${deviceId}|${showId}|${season}|${episode}|${index}|${text}`);
}

async function verifyTurns(env: Env, deviceId: string, showId: number, season: number,
                           episode: number, turns: Turn[]): Promise<void> {
  for (const [index, turn] of turns.entries()) {
    // Порядок строгий: Мончик, ученик, Мончик… и последним — ученик.
    const expected = index % 2 === 0 ? "monchik" : "learner";
    if (turn.speaker !== expected) throw new ApiError(400, "turns_tampered");
    if (turn.speaker !== "monchik") continue;
    const signature = await turnSignature(env, deviceId, showId, season, episode, index, turn.text);
    if (!turn.sig || !constantTimeEqual(signature, turn.sig)) {
      throw new ApiError(400, "turns_tampered");
    }
  }
  if (turns.length > 0 && turns[turns.length - 1]?.speaker !== "learner") {
    throw new ApiError(400, "turns_tampered");
  }
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
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
    const sig = record?.sig;
    const limit = speaker === "learner" ? 600 : 1_200;
    if ((speaker !== "learner" && speaker !== "monchik")
        || typeof text !== "string" || text.length > limit) {
      throw new ApiError(400, "invalid_field", "turns");
    }
    if (sig !== undefined && (typeof sig !== "string" || !/^[0-9a-f]{64}$/.test(sig))) {
      throw new ApiError(400, "invalid_field", "turns");
    }
    return { speaker, text, ...(typeof sig === "string" ? { sig } : {}) };
  });
  if (turns.filter((turn) => turn.speaker === "learner").length > MAX_LEARNER_TURNS) {
    throw new ApiError(400, "conversation_over");
  }
  return turns;
}

// MARK: - Monchik Help

/**
 * Помощник по приложению — бесплатно, без подписки: вопрос «как отменить
 * подписку» не должен требовать подписки. Поэтому лимиты строже всего
 * остального: несколько вопросов в минуту и полтора десятка в день на
 * устройство, плюс общий дневной потолок на весь сервер — чтобы тысяча
 * фальшивых устройств не превратила помощника в дыру в бюджете.
 */
async function help(request: Request, env: Env, deps: Deps): Promise<Response> {
  const { device } = await context(request, env, deps);
  const now = deps.now();
  const body = await readJson(request, 4_000);
  const question = str(body, "question", HELP_QUESTION_LIMIT);
  const language = oneOf(body, "language", LANGUAGES)!;

  await hit(env.DB, "help-min:" + device.id, 3, 60, now);
  await hit(env.DB, "help-day:" + device.id, 15, 86_400, now);
  await hit(env.DB, "help-all", intVar(env.HELP_DAILY_CAP, 2_000), 86_400, now);

  const result = await deps.claude.complete({
    system: helpSystem(language),
    messages: [{ role: "user", content: helpUserMessage(question) }],
    maxTokens: HELP_MAX_TOKENS,
    schema: HELP_SCHEMA as unknown as Record<string, unknown>,
  });
  await env.DB.prepare(
    `INSERT INTO usage_log (entitlement_id, device_id, kind, input_tokens, output_tokens, units, created_at)
     VALUES ('free', ?, 'help', ?, ?, ?, ?)`,
  ).bind(device.id, result.inputTokens, result.outputTokens,
    units(result.inputTokens, result.outputTokens), now).run();

  const reply = parseHelpReply(result.text, language);
  if (!reply) throw new ApiError(502, "model_error");
  return json(reply);
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
