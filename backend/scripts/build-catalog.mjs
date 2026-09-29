#!/usr/bin/env node
/**
 * Сборка каталога: топ-50 сериалов, первый сезон, слова к каждой серии.
 *
 *   npm run catalog -- plan      # найти сериалы и серии в TVMaze, оценить цену
 *   npm run catalog -- submit    # отправить пакет в Message Batches API (−50% к цене)
 *   npm run catalog -- status    # как идёт обработка
 *   npm run catalog -- collect   # забрать ответы → catalog/out/seed.sql
 *
 * Наборы, собранные заранее (catalog/words/*.txt, без модели и без ключа):
 *
 *   npm run catalog -- local           # → каталог в приложении + seed.sql, если есть plan.json
 *   npm run catalog -- local --check   # CI: каталог в приложении совпадает с исходником
 *
 * Ключ Anthropic — из ANTHROPIC_API_KEY (или профиля `ant auth login`);
 * в репозиторий и в файлы он не пишется. Модель — --model (по умолчанию
 * та же быстрая модель, что делает наборы в приложении).
 */
import Anthropic from "@anthropic-ai/sdk";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import {
  CATALOG_MAX_TOKENS, CATALOG_SCHEMA, CATALOG_SYSTEM, buildBundle, cleanNotes, customId,
  decksFromBundle, episodeCode, estimateCost, parseCustomId, parseWordsFile, seedSQL, userMessage,
} from "./catalog-lib.mjs";

const OUT = "catalog/out";
const PLAN = `${OUT}/plan.json`;
const STATE = `${OUT}/batch.json`;
const TVMAZE = "https://api.tvmaze.com";

function arg(name, fallback) {
  const index = process.argv.indexOf(`--${name}`);
  return index > 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}
const model = arg("model", "claude-haiku-4-5");
const command = process.argv[2];

async function tvmaze(path) {
  // TVMaze просит не больше 20 запросов за 10 секунд.
  await new Promise((resolve) => setTimeout(resolve, 600));
  const response = await fetch(TVMAZE + path);
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`TVMaze ${response.status} для ${path}`);
  return response.json();
}

function plainText(html) {
  return (html ?? "").replace(/<br\s*\/?>|<\/p>/gi, "\n").replace(/<[^>]+>/g, "")
    .replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&nbsp;/g, " ")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
    .split("\n").map((line) => line.trim()).filter(Boolean).join("\n");
}

async function plan() {
  const { shows } = JSON.parse(readFileSync("catalog/shows.json", "utf8"));
  const planned = [];
  for (const entry of shows) {
    const found = await tvmaze(`/singlesearch/shows?q=${encodeURIComponent(entry.name)}`);
    const year = Number((found?.premiered ?? "").slice(0, 4));
    if (!found || (entry.year && year && Math.abs(year - entry.year) > 1)) {
      console.warn(`✗ ${entry.name} (${entry.year}): не найден или другой год — проверь руками`);
      continue;
    }
    const episodes = ((await tvmaze(`/shows/${found.id}/episodes`)) ?? [])
      .filter((item) => item.season === 1 && Number.isInteger(item.number))
      .map((item) => ({ season: 1, number: item.number, name: item.name ?? "",
                        summary: plainText(item.summary).slice(0, 3000) }));
    planned.push({ id: found.id, name: found.name, year, rank: entry.rank, accent: entry.accent,
                   posterURL: (found.image?.medium ?? "").replace(/^http:/, "https:") || null, episodes });
    console.log(`✓ ${found.name}: ${episodes.length} серий`);
  }
  mkdirSync(OUT, { recursive: true });
  writeFileSync(PLAN, JSON.stringify(planned, null, 2));
  const total = planned.reduce((sum, show) => sum + show.episodes.length, 0);
  console.log(`\nСериалов: ${planned.length}, серий: ${total}.`);
  console.log(`Примерная цена через Batch API (${model}): $${estimateCost(model, total)}`);
}

async function submit() {
  if (!existsSync(PLAN)) throw new Error("Сначала: npm run catalog -- plan");
  if (existsSync(STATE)) throw new Error(`Пакет уже отправлен (${STATE}). Удали файл, чтобы отправить заново.`);
  const shows = JSON.parse(readFileSync(PLAN, "utf8"));
  const requests = shows.flatMap((show) => show.episodes.map((episode) => ({
    custom_id: customId(show.id, episode.season, episode.number),
    params: {
      model,
      max_tokens: CATALOG_MAX_TOKENS,
      system: CATALOG_SYSTEM,
      messages: [{ role: "user", content: userMessage(show, episode) }],
      output_config: { format: { type: "json_schema", schema: CATALOG_SCHEMA } },
    },
  })));
  const client = new Anthropic();
  const batch = await client.messages.batches.create({ requests });
  writeFileSync(STATE, JSON.stringify({ id: batch.id, model, createdAt: new Date().toISOString() }, null, 2));
  console.log(`Отправлено ${requests.length} запросов, пакет ${batch.id}. Обычно готово за час.`);
}

async function status() {
  const { id } = JSON.parse(readFileSync(STATE, "utf8"));
  const batch = await new Anthropic().messages.batches.retrieve(id);
  console.log(`${batch.processing_status}:`, batch.request_counts);
}

async function collect() {
  const { id } = JSON.parse(readFileSync(STATE, "utf8"));
  const client = new Anthropic();
  const batch = await client.messages.batches.retrieve(id);
  if (batch.processing_status !== "ended") throw new Error(`Пакет ещё идёт: ${batch.processing_status}`);
  const shows = JSON.parse(readFileSync(PLAN, "utf8"));
  const byId = new Map(shows.map((show) => [show.id, show]));
  const decks = [];
  const failed = [];
  // Ответы приходят в любом порядке — сопоставляем по custom_id.
  for await (const result of await client.messages.batches.results(id)) {
    const key = parseCustomId(result.custom_id);
    const show = key && byId.get(key.showId);
    const episode = show?.episodes.find((item) => item.number === key.episode);
    if (!key || !show || !episode) continue;
    if (result.result.type !== "succeeded" || result.result.message.stop_reason !== "end_turn") {
      failed.push(result.custom_id);
      continue;
    }
    const text = result.result.message.content.map((block) => (block.type === "text" ? block.text : "")).join("");
    const notes = cleanNotes(text);
    if (notes.length < 5) { failed.push(result.custom_id); continue; }
    const code = episodeCode(key.season, key.episode);
    decks.push({ ...key, title: episode.name ? `${code} · ${episode.name}` : code, notes });
  }
  const withDecks = shows.filter((show) => decks.some((deck) => deck.showId === show.id));
  writeFileSync(`${OUT}/seed.sql`, seedSQL(withDecks, decks));
  writeFileSync(`${OUT}/decks.json`, JSON.stringify(decks, null, 2));
  console.log(`Наборов: ${decks.length}, не получилось: ${failed.length}.`);
  if (failed.length) console.log("Повторить можно отдельным пакетом:", failed.join(", "));
  console.log(`Загрузить: npx wrangler d1 execute recap --remote --file ${OUT}/seed.sql`);
}

const WORDS = "catalog/words";
const APP_CATALOG = "../App/Resources/Catalog";

async function local() {
  const check = process.argv.includes("--check");
  const files = existsSync(WORDS) ? readdirSync(WORDS).filter((name) => name.endsWith(".txt")).sort() : [];
  const parsed = files.map((name) => parseWordsFile(readFileSync(`${WORDS}/${name}`, "utf8"), name));
  const { shows } = JSON.parse(readFileSync("catalog/shows.json", "utf8"));
  const bundle = buildBundle(parsed, shows);
  const errors = [...parsed.flatMap((item) => item.errors), ...bundle.errors];
  if (errors.length) {
    console.error(errors.join("\n"));
    process.exit(1);
  }
  // Компактный JSON: в приложении его читает машина, а сверяют глазами исходник.
  const outputs = { "catalog-index.json": JSON.stringify(bundle.index) + "\n" };
  for (const [resource, file] of Object.entries(bundle.files)) {
    outputs[`${resource}.json`] = JSON.stringify(file) + "\n";
  }
  if (check) {
    const stale = Object.entries(outputs).filter(([name, content]) =>
      !existsSync(`${APP_CATALOG}/${name}`) || readFileSync(`${APP_CATALOG}/${name}`, "utf8") !== content);
    const extra = existsSync(APP_CATALOG)
      ? readdirSync(APP_CATALOG).filter((name) => name.endsWith(".json") && !(name in outputs)) : [];
    if (stale.length || extra.length) {
      console.error("Каталог в приложении устарел — запусти `npm run catalog -- local`:",
                    [...stale.map(([name]) => name), ...extra].join(", "));
      process.exit(1);
    }
    console.log(`Каталог в приложении совпадает с исходником: сериалов ${bundle.index.shows.length}.`);
    return;
  }
  mkdirSync(APP_CATALOG, { recursive: true });
  for (const [name, content] of Object.entries(outputs)) writeFileSync(`${APP_CATALOG}/${name}`, content);
  const words = bundle.index.shows.reduce((sum, show) => sum + show.words, 0);
  const episodes = bundle.index.shows.reduce((sum, show) => sum + show.episodes, 0);
  console.log(`Приложение: сериалов ${bundle.index.shows.length}, серий ${episodes}, слов ${words}.`);

  if (!existsSync(PLAN)) {
    console.log("Для базы сервера нужны номера TVMaze: npm run catalog -- plan (нужна сеть), потом снова local.");
    return;
  }
  const { shows: seedShows, decks, skipped } = decksFromBundle(bundle, JSON.parse(readFileSync(PLAN, "utf8")));
  mkdirSync(OUT, { recursive: true });
  writeFileSync(`${OUT}/seed.sql`, seedSQL(seedShows, decks));
  console.log(`База: наборов ${decks.length}${skipped.length ? `, без номера TVMaze: ${skipped.join(", ")}` : ""}.`);
  console.log(`Загрузить: npx wrangler d1 execute recap --remote --file ${OUT}/seed.sql`);
}

const commands = { plan, submit, status, collect, local };
if (!commands[command]) {
  console.log("Команды: plan | submit | status | collect | local   (флаг --model, по умолчанию claude-haiku-4-5)");
  process.exit(1);
}
await commands[command]();
