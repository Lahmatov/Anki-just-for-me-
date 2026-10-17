import { ApiError } from "./http";
import { hmacHex, sha256Hex } from "./crypto";
import { hit } from "./ratelimit";
import type { Device } from "./auth";
import type { Deps, Env } from "./env";

/**
 * Служебный вход для запросов людей не из приложения (P-76): человек
 * потерял телефон или пишет письмом «удалите мои данные». В приложении
 * у него всё это есть кнопками; здесь — то же самое по коду поддержки,
 * теми же функциями, что и кнопки.
 *
 * Пока секрета ADMIN_TOKEN нет, маршрутов как будто не существует (404):
 * служебная дверь закрыта по умолчанию.
 */
export async function requireAdmin(request: Request, env: Env, deps: Deps): Promise<void> {
  if (!env.ADMIN_TOKEN) throw new ApiError(404, "not_found");
  // Подбор секрета бессмыслен (256 бит), но и пробовать много раз нельзя.
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  await hit(env.DB, "admin:" + await hmacHex(env.PROMO_PEPPER, ip), 30, 3600, deps.now());
  const match = /^Bearer (\S{32,256})$/.exec(request.headers.get("authorization") ?? "");
  if (!match?.[1] || !await sameSecret(match[1], env.ADMIN_TOKEN)) {
    throw new ApiError(401, "unauthorized");
  }
}

/**
 * Сравнение за одинаковое время: сравниваются хеши, а не строки, — длина
 * и первый несовпавший знак не выдают себя по времени ответа.
 */
async function sameSecret(given: string, expected: string): Promise<boolean> {
  const [a, b] = await Promise.all([sha256Hex(given), sha256Hex(expected)]);
  let difference = 0;
  for (let index = 0; index < a.length; index++) difference |= a.charCodeAt(index) ^ b.charCodeAt(index);
  return difference === 0;
}

/** «ABCD-1234» или «abcd1234» → первые 8 знаков номера устройства; иначе null. */
export function normalizeSupportCode(code: unknown): string | null {
  if (typeof code !== "string") return null;
  const match = /^\s*([0-9a-f]{4})-?([0-9a-f]{4})\s*$/i.exec(code);
  return match ? (match[1]! + match[2]!).toLowerCase() : null;
}

const TICKET_ID = /^\s*(R-[2-9A-HJKMNP-Z]{6})\s*$/i;

/**
 * Устройство по коду поддержки или номеру обращения («R-7K2Q9X»): человек
 * чаще помнит номер своего обращения «Мои данные», чем код из «Профиля».
 * Код — 32 бита номера устройства: совпадение двух устройств возможно,
 * и тогда лучше отказать, чем стереть чужое.
 */
export async function deviceBySupportCode(db: D1Database, code: unknown): Promise<Device> {
  const ticket = typeof code === "string" ? TICKET_ID.exec(code)?.[1]?.toUpperCase() : undefined;
  if (ticket) {
    const device = await db.prepare(
      `SELECT d.id, d.entitlement_id, d.account_id, d.last_seen_at
       FROM support_tickets t JOIN devices d ON d.id = t.device_id WHERE t.id = ?`,
    ).bind(ticket).first<Device>();
    if (!device) throw new ApiError(404, "device_not_found");
    return device;
  }
  const prefix = normalizeSupportCode(code);
  if (!prefix) throw new ApiError(400, "invalid_input", "supportCode");
  const rows = await db.prepare(
    "SELECT id, entitlement_id, account_id, last_seen_at FROM devices WHERE substr(id, 1, 8) = ? LIMIT 2",
  ).bind(prefix).all<Device>();
  if (rows.results.length === 0) throw new ApiError(404, "device_not_found");
  if (rows.results.length > 1) throw new ApiError(409, "ambiguous_code");
  return rows.results[0]!;
}
