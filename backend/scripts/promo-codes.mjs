#!/usr/bin/env node
/**
 * Выпуск промокодов.
 *
 *   node scripts/promo-codes.mjs --count 100 --days 30 --batch launch
 *
 * Пишет в secrets/ (папка в .gitignore — в репозиторий не попадает):
 *   promo-codes-<batch>.txt  — сами коды, раздавать людям;
 *   promo-seed-<batch>.sql   — только HMAC кодов, загрузить в базу:
 *     npx wrangler d1 execute recap --remote --file secrets/promo-seed-<batch>.sql
 *
 * Перец — секрет PROMO_PEPPER Worker. Берётся из переменной окружения или
 * secrets/promo-pepper.txt; если его нет — создаётся новый (один раз, до
 * первого выпуска: смена перца делает все старые коды недействительными).
 */
import { createHmac, randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";

const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

function arg(name, fallback) {
  const index = process.argv.indexOf(`--${name}`);
  return index > 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

const count = Number(arg("count", "100"));
const days = Number(arg("days", "30"));
const units = Number(arg("units", "0"));  // 0 — по умолчанию сервера (PROMO_UNITS)
const batch = arg("batch", "launch").replace(/[^a-z0-9-]/gi, "");
const expires = arg("expires", "");       // ГГГГ-ММ-ДД, после — код не принимается

if (!Number.isInteger(count) || count < 1 || count > 10_000) throw new Error("--count 1…10000");
if (!Number.isInteger(days) || days < 1 || days > 3650) throw new Error("--days 1…3650");

mkdirSync("secrets", { recursive: true });
const pepperFile = "secrets/promo-pepper.txt";
let pepper = process.env.PROMO_PEPPER;
if (!pepper && existsSync(pepperFile)) pepper = readFileSync(pepperFile, "utf8").trim();
if (!pepper) {
  pepper = randomBytes(32).toString("base64url");
  writeFileSync(pepperFile, pepper + "\n", { mode: 0o600 });
  console.log(`Создан новый перец: ${pepperFile}. Загрузить в Worker:`);
  console.log("  npx wrangler secret put PROMO_PEPPER   (и вставить содержимое файла)");
}
if (pepper.length < 32) throw new Error("PROMO_PEPPER короче 32 символов");

function code() {
  // Каждый байт даёт 5 равномерных бит (256 делится на 32).
  return Array.from(randomBytes(16), (byte) => CROCKFORD[byte & 31]).join("");
}

const seen = new Set();
const codes = [];
while (codes.length < count) {
  const next = code();
  if (!seen.has(next)) { seen.add(next); codes.push(next); }
}

const now = Math.floor(Date.now() / 1000);
const expiresAt = expires ? Math.floor(Date.parse(expires + "T23:59:59Z") / 1000) : null;
const rows = codes.map((value) => {
  const hash = createHmac("sha256", pepper).update("promo:" + value).digest("hex");
  return `('${hash}', '${batch}', ${days}, ${units}, ${now}, ${expiresAt ?? "NULL"})`;
});

const formatted = codes.map((value) => "RECAP-" + value.match(/.{4}/g).join("-"));
writeFileSync(`secrets/promo-codes-${batch}.txt`, formatted.join("\n") + "\n", { mode: 0o600 });
writeFileSync(`secrets/promo-seed-${batch}.sql`,
  "INSERT INTO promo_codes (hash, batch, days, units, created_at, expires_at) VALUES\n"
    + rows.join(",\n") + ";\n", { mode: 0o600 });

console.log(`Готово: ${count} кодов на ${days} дней, партия «${batch}».`);
console.log(`  коды:  secrets/promo-codes-${batch}.txt`);
console.log(`  база:  secrets/promo-seed-${batch}.sql`);
