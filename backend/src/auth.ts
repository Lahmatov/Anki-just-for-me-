import { ApiError } from "./http";
import { base64url, sha256Hex, toHex } from "./crypto";
import type { Deps } from "./env";

export interface Device {
  id: string;
  entitlement_id: string | null;
  /** Аккаунт, если на телефоне выполнен вход через Apple. */
  account_id: string | null;
  last_seen_at: number;
}

/**
 * Регистрация устройства: сервер выдаёт случайный токен в 256 бит и хранит
 * только его SHA-256. Токен живёт в Keychain телефона. Аккаунт (вход через
 * Apple) — необязательная надстройка: доступ к ИИ даёт не регистрация,
 * а подписка или промокод, так что тысяча фальшивых устройств ничего не получает.
 */
export async function registerDevice(db: D1Database, deps: Deps): Promise<string> {
  const token = base64url(deps.randomBytes(32));
  const id = toHex(deps.randomBytes(16));
  const now = deps.now();
  await db.prepare(
    "INSERT INTO devices (id, token_hash, created_at, last_seen_at) VALUES (?, ?, ?, ?)",
  ).bind(id, await sha256Hex(token), now, now).run();
  return token;
}

/** Устройство по заголовку `Authorization: Bearer <токен>`. */
export async function authenticate(request: Request, db: D1Database, deps: Deps): Promise<Device> {
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(header);
  if (!match?.[1]) throw new ApiError(401, "unauthorized");
  const device = await db.prepare(
    "SELECT id, entitlement_id, account_id, last_seen_at FROM devices WHERE token_hash = ?",
  ).bind(await sha256Hex(match[1])).first<Device>();
  if (!device) throw new ApiError(401, "unauthorized");

  // Отметка «был в сети» — не чаще раза в час: запись на каждый запрос
  // только нагружала бы базу.
  const now = deps.now();
  if (now - device.last_seen_at > 3600) {
    await db.prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?").bind(now, device.id).run();
  }
  return device;
}
