#!/usr/bin/env node
/**
 * Обращения в поддержку (P-72, docs/support.md).
 *
 *   npm run support                       — открытые обращения, старые сверху
 *   npm run support -- show R-7K2Q9X      — одно обращение целиком
 *   npm run support -- reply R-7K2Q9X "Текст ответа"  — ответ появится в приложении
 *   npm run support -- close R-7K2Q9X     — закрыть без ответа (спам, дубль)
 *
 * Добавь --staging, чтобы работать с тестовым сервером. Нужен вход в
 * Cloudflare (`npx wrangler login`) — данные людей не покидают Cloudflare,
 * кроме того, что ты читаешь в терминале.
 */
import { execFileSync } from "node:child_process";

const args = process.argv.slice(2).filter((item) => item !== "--staging");
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
  default:
    throw new Error(`Неизвестная команда ${command}: list, show, reply, close`);
}
