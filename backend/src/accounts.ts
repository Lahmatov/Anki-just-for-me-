import { ApiError } from "./http";
import { hmacHex, open, seal, toHex } from "./crypto";
import { better, entitlementOf, linkDevice, linkDeviceIfRoom } from "./quota";
import { exchangeCode, revokeToken, siwaConfigured, verifyIdentityToken } from "./siwa";
import type { Device } from "./auth";
import type { Deps, Env } from "./env";
import { deleteBackupsStatements } from "./backups";

/**
 * Аккаунт — необязательный слой над устройствами.
 *
 * Без входа доступ живёт на устройстве, как и раньше. После входа доступ
 * принадлежит аккаунту: промокод, погашенный на одном телефоне, работает
 * на всех телефонах этого человека (в пределах лимита устройств), а выход
 * забирает доступ аккаунта с этого телефона.
 */
export interface Account {
  id: string;
  entitlement_id: string | null;
  refresh_token_enc: string | null;
  created_at: number;
  last_seen_at: number;
}

/** Назначение ключа шифрования — см. `seal` в crypto.ts. */
const REFRESH_PURPOSE = "apple-refresh-token";

export async function accountOf(db: D1Database, id: string | null): Promise<Account | null> {
  if (!id) return null;
  return db.prepare(
    "SELECT id, entitlement_id, refresh_token_enc, created_at, last_seen_at FROM accounts WHERE id = ?",
  ).bind(id).first<Account>();
}

export interface SignInInput {
  identityToken: string;
  authorizationCode: string;
  nonce: string;
}

export async function signIn(
  env: Env, deps: Deps, device: Device, input: SignInInput, maxDevices: number,
): Promise<void> {
  if (!siwaConfigured(env)) throw new ApiError(503, "signin_not_configured");
  const claims = await verifyIdentityToken(deps, input.identityToken, env.BUNDLE_ID, input.nonce);
  const refreshToken = await exchangeCode(env, deps, input.authorizationCode, claims.sub);

  const db = env.DB;
  const now = deps.now();
  const subHash = await hmacHex(env.PROMO_PEPPER, "apple:" + claims.sub);
  const sealed = await seal(env.PROMO_PEPPER, REFRESH_PURPOSE, refreshToken, deps.randomBytes);

  let account = await db.prepare(
    "SELECT id, entitlement_id, refresh_token_enc, created_at, last_seen_at FROM accounts WHERE apple_sub_hash = ?",
  ).bind(subHash).first<Account>();
  if (account) {
    await db.prepare("UPDATE accounts SET refresh_token_enc = ?, last_seen_at = ? WHERE id = ?")
      .bind(sealed, now, account.id).run();
  } else {
    const id = toHex(deps.randomBytes(16));
    await db.prepare(
      `INSERT INTO accounts (id, apple_sub_hash, refresh_token_enc, created_at, last_seen_at)
       VALUES (?, ?, ?, ?, ?)`,
    ).bind(id, subHash, sealed, now, now).run();
    account = { id, entitlement_id: null, refresh_token_enc: sealed, created_at: now, last_seen_at: now };
  }

  // Телефон был в другом аккаунте — сначала честный выход из него.
  if (device.account_id && device.account_id !== account.id) await signOut(db, device);

  await db.prepare("UPDATE devices SET account_id = ? WHERE id = ?").bind(account.id, device.id).run();
  device.account_id = account.id;

  // Лучший из двух доступов становится доступом аккаунта. Вход — явное
  // действие, поэтому здесь можно вытеснить самое молчаливое устройство.
  const winner = better(
    await entitlementOf(db, account.entitlement_id, now),
    await entitlementOf(db, device.entitlement_id, now), now);
  if (!winner) return;
  if (winner.id !== account.entitlement_id) {
    await db.prepare("UPDATE accounts SET entitlement_id = ? WHERE id = ?").bind(winner.id, account.id).run();
  }
  if (winner.id !== device.entitlement_id) {
    await linkDevice(db, device.id, winner.id, maxDevices);
    device.entitlement_id = winner.id;
  }
}

/**
 * Выход: телефон отвязывается от аккаунта и теряет доступ аккаунта.
 * Подписка, купленная с Apple ID этого телефона, вернётся сама — приложение
 * после выхода сверяется с App Store.
 */
export async function signOut(db: D1Database, device: Device): Promise<void> {
  const account = await accountOf(db, device.account_id);
  const statements = [
    db.prepare("UPDATE devices SET account_id = NULL WHERE id = ?").bind(device.id),
  ];
  if (account?.entitlement_id && account.entitlement_id === device.entitlement_id) {
    statements.push(db.prepare("UPDATE devices SET entitlement_id = NULL WHERE id = ?").bind(device.id));
    device.entitlement_id = null;
  }
  await db.batch(statements);
  device.account_id = null;
}

/**
 * Удалить аккаунт (правило App Store 5.1.1(v)): сначала отозвать вход у
 * Apple — не вышло, ничего не удаляем, пусть человек повторит. Потом
 * отвязать все телефоны, стереть промо-доступ аккаунта и сам аккаунт.
 * Сами телефоны и их данные остаются: для этого есть «Удалить все данные».
 */
export async function deleteAccount(env: Env, deps: Deps, device: Device): Promise<void> {
  const db = env.DB;
  const account = await accountOf(db, device.account_id);
  if (!account) throw new ApiError(409, "not_signed_in");
  if (account.refresh_token_enc) {
    if (!siwaConfigured(env)) throw new ApiError(503, "signin_not_configured");
    let refreshToken: string;
    try {
      refreshToken = await open(env.PROMO_PEPPER, REFRESH_PURPOSE, account.refresh_token_enc);
    } catch {
      // Токен не расшифровать (сменился секрет) — отзывать нечем. Удаление
      // всё равно выполняется: держать аккаунт из-за этого нельзя.
      refreshToken = "";
    }
    if (refreshToken) await revokeToken(env, deps, refreshToken);
  }

  const statements = [];
  if (account.entitlement_id) {
    statements.push(db.prepare(
      "UPDATE devices SET entitlement_id = NULL WHERE account_id = ? AND entitlement_id = ?",
    ).bind(account.id, account.entitlement_id));
    // Промокод принадлежал аккаунту. Подписка — покупке в App Store: её
    // запись живёт, пока её не подберёт «Восстановить покупки» или чистка.
    statements.push(db.prepare("DELETE FROM entitlements WHERE id = ? AND kind = 'promo'")
      .bind(account.entitlement_id));
  }
  // Снимки аккаунта — его данные: удаление аккаунта без них было бы неполным.
  statements.push(...deleteBackupsStatements(db, account.id));
  statements.push(db.prepare("UPDATE devices SET account_id = NULL WHERE account_id = ?").bind(account.id));
  statements.push(db.prepare("DELETE FROM accounts WHERE id = ?").bind(account.id));
  await db.batch(statements);
  device.account_id = null;
  if (device.entitlement_id === account.entitlement_id) device.entitlement_id = null;
}

/**
 * Подстроить устройство под аккаунт при каждом запросе: доступ, купленный
 * или погашенный на другом телефоне, появляется здесь сам — если есть
 * свободное место. А если лучший доступ у самого телефона (подписка его
 * Apple ID), его забирает аккаунт.
 */
export async function followAccount(
  db: D1Database, device: Device, now: number, maxDevices: number,
): Promise<void> {
  const account = await accountOf(db, device.account_id);
  if (!account) {
    device.account_id = null;
    return;
  }
  if (now - account.last_seen_at > 3600) {
    await db.prepare("UPDATE accounts SET last_seen_at = ? WHERE id = ?").bind(now, account.id).run();
  }
  if (account.entitlement_id === device.entitlement_id) return;

  const accountEntitlement = await entitlementOf(db, account.entitlement_id, now);
  const deviceEntitlement = await entitlementOf(db, device.entitlement_id, now);
  const winner = better(accountEntitlement, deviceEntitlement, now);
  if (!winner) return;
  if (winner.id === device.entitlement_id) {
    await db.prepare("UPDATE accounts SET entitlement_id = ? WHERE id = ?").bind(winner.id, account.id).run();
  } else if (await linkDeviceIfRoom(db, device.id, winner.id, maxDevices)) {
    device.entitlement_id = winner.id;
  }
}

/**
 * После покупки или промокода на телефоне в аккаунте: доступ телефона
 * становится доступом аккаунта — если он лучше того, что у аккаунта был.
 */
export async function shareWithAccount(db: D1Database, deviceId: string, now: number): Promise<void> {
  const row = await db.prepare("SELECT account_id, entitlement_id FROM devices WHERE id = ?")
    .bind(deviceId).first<{ account_id: string | null; entitlement_id: string | null }>();
  const account = await accountOf(db, row?.account_id ?? null);
  if (!account || !row?.entitlement_id || row.entitlement_id === account.entitlement_id) return;
  const deviceEntitlement = await entitlementOf(db, row.entitlement_id, now);
  const winner = better(deviceEntitlement, await entitlementOf(db, account.entitlement_id, now), now);
  if (winner && winner.id === row.entitlement_id) {
    await db.prepare("UPDATE accounts SET entitlement_id = ? WHERE id = ?").bind(winner.id, account.id).run();
  }
}
