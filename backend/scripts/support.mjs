#!/usr/bin/env node
/**
 * Обращения в поддержку (P-72, docs/support.md).
 *
 *   npm run support                       — открытые обращения, старые сверху
 *   npm run support -- show R-7K2Q9X      — одно обращение целиком
 *   npm run support -- reply R-7K2Q9X "Текст ответа"  — ответ появится в приложении
 *   npm run support -- close R-7K2Q9X     — закрыть без ответа (спам, дубль)
 *
 * Просьбы о данных письмом (P-76, docs/gdpr.md) — по коду поддержки из «Профиля»
 * или по номеру обращения (R-7K2Q9X вместо ABCD-1234):
 *   npm run support -- export ABCD-1234        — всё, что сервер знает, в файл data-ABCD-1234.json
 *   npm run support -- erase ABCD-1234 --yes   — удалить аккаунт и телефон, как кнопки в приложении
 * Эти две идут через сервер, а не в базу напрямую: так удаление то же самое,
 * что по кнопке (вход у Apple отзывается, снимки в R2 стираются). Нужны
 * RECAP_URL (или RECAP_STAGING_URL с --staging) и RECAP_ADMIN_TOKEN —
 * тот же секрет, что `wrangler secret put ADMIN_TOKEN`.
 *
 * Добавь --staging, чтобы работать с тестовым сервером. Нужен вход в
 * Cloudflare (`npx wrangler login`) — данные людей не покидают Cloudflare,
 * кроме того, что ты читаешь в терминале.
 */
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const args = process.argv.slice(2).filter((item) => item !== "--staging" && item !== "--yes");
const confirmed = process.argv.includes("--yes");
const staging = process.argv.includes("--staging");
const database = staging ? "recap-staging" : "recap";
const [command = "list", id, ...rest] = args;

/** Значение для SQL: кавычки удваиваются, так текст ответа не ломает запрос. */
const quote = (value) => `'${String(value).replace(/'/g, "''")}'`;

function sql(statement) {
  const output = execFileSync("npx", ["--yes", "wrangler@4", "d1", "execute", database, "--remote", "--json",
                                      ...(staging ? ["--env", "staging"] : []), "--command", statement],
                              { encoding: "utf8" });
  return JSON.parse(output)[0]?.results ?? [];
}

function requireId() {
  if (!/^R-[2-9A-HJKMNP-Z]{6}$/.test(id ?? "")) throw new Error("Номер обращения вида R-7K2Q9X");
}

/** Служебный маршрут сервера; секрет — из переменной окружения, не из аргументов (история shell). */
async function admin(path, supportCode) {
  const base = process.env[staging ? "RECAP_STAGING_URL" : "RECAP_URL"];
  const secret = process.env.RECAP_ADMIN_TOKEN;
  if (!base || !secret) {
    throw new Error(`Нужны ${staging ? "RECAP_STAGING_URL" : "RECAP_URL"} и RECAP_ADMIN_TOKEN`);
  }
  const response = await fetch(new URL(path, base), {
    method: "POST",
    headers: { authorization: `Bearer ${secret}`, "content-type": "application/json" },
    body: JSON.stringify({ supportCode }),
  });
  const body = await response.json().catch(() => ({}));
  const reasons = {
    401: "секрет не подходит", 404: "такого кода нет (или ADMIN_TOKEN не задан на сервере)",
    409: "под этим кодом два устройства — попроси номер обращения (R-…) и повтори с ним",
  };
  if (!response.ok) throw new Error(`Сервер: ${response.status} ${reasons[response.status] ?? body.error ?? ""}`);
  return body;
}

const date = (seconds) => new Date(seconds * 1000).toISOString().replace("T", " ").slice(0, 16);

switch (command) {
  case "list": {
    const rows = sql(`SELECT id, category, substr(message, 1, 80) AS preview, created_at
                      FROM support_tickets WHERE status = 'open' ORDER BY created_at LIMIT 100`);
    if (rows.length === 0) console.log("Открытых обращений нет.");
    for (const row of rows) console.log(`${row.id}  ${date(row.created_at)}  [${row.category}]  ${row.preview}`);
    break;
  }
  case "show": {
    requireId();
    const [row] = sql(`SELECT * FROM support_tickets WHERE id = ${quote(id)}`);
    if (!row) throw new Error(`Обращения ${id} нет`);
    console.log(`${row.id} · ${row.category} · ${row.status} · ${date(row.created_at)}`);
    console.log(`Почта: ${row.contact ?? "нет — ответ только в приложении"}`);
    console.log(`Диагностика: ${row.diagnostics ?? "нет"}\n`);
    console.log(row.message);
    if (row.reply) console.log(`\n— Ответ:\n${row.reply}`);
    break;
  }
  case "reply": {
    requireId();
    const text = rest.join(" ").trim();
    if (!text) throw new Error("Текст ответа после номера");
    sql(`UPDATE support_tickets SET reply = ${quote(text)}, status = 'answered',
         updated_at = unixepoch() WHERE id = ${quote(id)}`);
    console.log(`Ответ на ${id} сохранён — человек увидит его в «Помощь → Мои обращения».`);
    break;
  }
  case "close": {
    requireId();
    sql(`UPDATE support_tickets SET status = 'closed', updated_at = unixepoch() WHERE id = ${quote(id)}`);
    console.log(`${id} закрыто.`);
    break;
  }
  case "export": {
    const data = await admin("/v1/admin/export", id);
    const file = `data-${data.supportCode}.json`;
    writeFileSync(file, JSON.stringify(data, null, 2));
    console.log(`Сохранено в ${file} — приложи к ответу человеку (GDPR, ст. 15 и 20).`);
    break;
  }
  case "erase": {
    if (!confirmed) {
      console.log(`Будут удалены телефон ${id}, его обращения, снимки и аккаунт, если вошёл.`);
      console.log("Отменить нельзя. Повтори с --yes.");
      break;
    }
    const result = await admin("/v1/admin/erase", id);
    console.log(`Удалено: телефон ${id}${result.account ? " и аккаунт (вход у Apple отозван)" : ""}.`);
    console.log("Подписка живёт в Apple ID — отменяет её сам человек в настройках Apple.");
    break;
  }
  default:
    throw new Error(`Неизвестная команда ${command}: list, show, reply, close, export, erase`);
}
