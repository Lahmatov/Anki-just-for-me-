import { ApiError } from "./http";
import { toHex } from "./crypto";
import type { Deps } from "./env";

/**
 * Единицы расхода: вход плюс выход с весом пять — так соотносятся цены
 * модели (у Haiku $1 и $5 за миллион). Лимит в единицах честно ограничивает
 * стоимость, а не число запросов.
 */
export const OUTPUT_WEIGHT = 5;

export function units(inputTokens: number, outputTokens: number): number {
  return Math.max(0, inputTokens) + OUTPUT_WEIGHT * Math.max(0, outputTokens);
}

export interface Entitlement {
  id: string;
  kind: "promo" | "subscription";
  units_per_period: number;
  used: number;
  /** Сумма действующих броней — считается запросом, в таблице её нет. */
  reserved: number;
  period_start: number;
  period_end: number;
  original_transaction_id: string | null;
  product_id: string | null;
}

export interface PlanStatus {
  plan: "none" | "promo" | "subscription";
  active: boolean;
  unitsTotal: number;
  unitsLeft: number;
  periodEnd: string | null;
}

/** Бронь старше этого — оборванный запрос: Worker столько не живёт. */
export const RESERVATION_TTL = 600;

export async function entitlementOf(
  db: D1Database, entitlementId: string | null, now: number,
): Promise<Entitlement | null> {
  if (!entitlementId) return null;
  return db.prepare(
    `SELECT e.*, COALESCE((SELECT SUM(amount) FROM reservations r
       WHERE r.entitlement_id = e.id AND r.created_at > ?2), 0) AS reserved
     FROM entitlements e WHERE e.id = ?1`,
  ).bind(entitlementId, now - RESERVATION_TTL).first<Entitlement>();
}

export function status(entitlement: Entitlement | null, now: number): PlanStatus {
  if (!entitlement) {
    return { plan: "none", active: false, unitsTotal: 0, unitsLeft: 0, periodEnd: null };
  }
  const active = entitlement.period_end > now;
  const left = active
    ? Math.max(0, entitlement.units_per_period - entitlement.used - entitlement.reserved)
    : 0;
  return {
    plan: entitlement.kind,
    active,
    unitsTotal: entitlement.units_per_period,
    unitsLeft: left,
    periodEnd: new Date(entitlement.period_end * 1000).toISOString(),
  };
}

/**
 * Бронь единиц до запроса к модели — одним INSERT … SELECT с условием:
 * запись появляется, только если лимит вмещает её вместе с остальными
 * действующими бронями. Параллельные запросы не могут вместе выйти за лимит.
 */
export async function reserve(
  db: D1Database, deps: Deps, entitlementId: string, amount: number,
): Promise<string> {
  const now = deps.now();
  const id = toHex(deps.randomBytes(16));
  const result = await db.prepare(
    `INSERT INTO reservations (id, entitlement_id, amount, created_at)
     SELECT ?1, e.id, ?2, ?3 FROM entitlements e
     WHERE e.id = ?4 AND e.period_end > ?3
       AND e.used + ?2 + COALESCE((SELECT SUM(amount) FROM reservations r
             WHERE r.entitlement_id = e.id AND r.created_at > ?5), 0) <= e.units_per_period`,
  ).bind(id, amount, now, entitlementId, now - RESERVATION_TTL).run();
  if ((result.meta.changes ?? 0) === 0) throw new ApiError(402, "quota_exceeded");
  return id;
}

/** Снять бронь и списать фактический расход (или ничего, если запрос упал). */
export async function settle(
  db: D1Database, entitlementId: string, reservationId: string, spent: number, now: number,
): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM reservations WHERE id = ?").bind(reservationId),
    db.prepare("UPDATE entitlements SET used = used + ?, updated_at = ? WHERE id = ?")
      .bind(spent, now, entitlementId),
  ]);
}

// MARK: - Промокод

/**
 * Промокод даёт доступ на `days` дней с месячным лимитом `unitsPerPeriod`.
 * Действующий промо-доступ продлевается; истёкший начинается заново;
 * к подписке промокод добавляет единицы в текущий период.
 */
export async function grantPromo(
  db: D1Database, deps: Deps, deviceId: string, current: Entitlement | null,
  days: number, unitsPerPeriod: number,
): Promise<void> {
  const now = deps.now();
  const seconds = days * 86_400;
  if (current && current.kind === "subscription" && current.period_end > now) {
    await db.prepare(
      "UPDATE entitlements SET units_per_period = units_per_period + ?, updated_at = ? WHERE id = ?",
    ).bind(unitsPerPeriod, now, current.id).run();
    return;
  }
  if (current && current.kind === "promo") {
    if (current.period_end > now) {
      await db.prepare(
        "UPDATE entitlements SET period_end = period_end + ?, updated_at = ? WHERE id = ?",
      ).bind(seconds, now, current.id).run();
    } else {
      await db.prepare(
        `UPDATE entitlements SET period_start = ?1, period_end = ?2, used = 0,
           units_per_period = ?3, updated_at = ?1 WHERE id = ?4`,
      ).bind(now, now + seconds, unitsPerPeriod, current.id).run();
    }
    return;
  }
  const id = toHex(deps.randomBytes(16));
  await db.batch([
    db.prepare(
      `INSERT INTO entitlements (id, kind, units_per_period, period_start, period_end, updated_at)
       VALUES (?, 'promo', ?, ?, ?, ?)`,
    ).bind(id, unitsPerPeriod, now, now + seconds, now),
    db.prepare("UPDATE devices SET entitlement_id = ? WHERE id = ?").bind(id, deviceId),
  ]);
}

// MARK: - Подписка

export interface VerifiedSubscription {
  originalTransactionId: string;
  productId: string;
  purchaseDate: number;
  expiresDate: number;
}

/**
 * Привязать проверенную у Apple подписку к устройству.
 *
 * Лимит — на покупку, а не на устройство: одна подписка на телефоне и
 * планшете делит одни единицы. Устройств на покупку — не больше
 * `maxDevices`: при превышении отвязывается то, что дольше всех молчит, —
 * смена телефона работает сама, а раздать подписку друзьям не выйдет.
 */
export async function applySubscription(
  db: D1Database, deps: Deps, deviceId: string, subscription: VerifiedSubscription,
  unitsPerPeriod: number, maxDevices: number,
): Promise<void> {
  const now = deps.now();
  const existing = await db.prepare(
    "SELECT * FROM entitlements WHERE original_transaction_id = ?",
  ).bind(subscription.originalTransactionId).first<Entitlement>();

  let entitlementId: string;
  if (!existing) {
    entitlementId = toHex(deps.randomBytes(16));
    await db.prepare(
      `INSERT INTO entitlements (id, kind, units_per_period, period_start, period_end,
         original_transaction_id, product_id, updated_at)
       VALUES (?, 'subscription', ?, ?, ?, ?, ?, ?)`,
    ).bind(entitlementId, unitsPerPeriod, subscription.purchaseDate, subscription.expiresDate,
      subscription.originalTransactionId, subscription.productId, now).run();
  } else {
    entitlementId = existing.id;
    if (subscription.expiresDate > existing.period_end) {
      // Подписка продлилась — новый период с чистым счётчиком.
      await db.prepare(
        `UPDATE entitlements SET period_start = ?1, period_end = ?2, used = 0,
           units_per_period = ?3, product_id = ?4, updated_at = ?5 WHERE id = ?6`,
      ).bind(subscription.purchaseDate, subscription.expiresDate, unitsPerPeriod,
        subscription.productId, now, entitlementId).run();
    }
  }

  await linkDevice(db, deviceId, entitlementId, maxDevices);
}

/**
 * Привязать устройство к доступу и уложиться в лимит устройств: лишним
 * становится то, что дольше всех молчит. Так смена телефона работает
 * сама, а раздать доступ друзьям не выйдет.
 */
export async function linkDevice(
  db: D1Database, deviceId: string, entitlementId: string, maxDevices: number,
): Promise<void> {
  await db.prepare("UPDATE devices SET entitlement_id = ? WHERE id = ?")
    .bind(entitlementId, deviceId).run();

  const linked = await db.prepare(
    "SELECT id FROM devices WHERE entitlement_id = ? ORDER BY last_seen_at DESC, created_at DESC",
  ).bind(entitlementId).all<{ id: string }>();
  const extra = linked.results.filter((row) => row.id !== deviceId).slice(maxDevices - 1);
  for (const row of extra) {
    await db.prepare("UPDATE devices SET entitlement_id = NULL WHERE id = ?").bind(row.id).run();
  }
}

/**
 * Привязать, только если есть свободное место, — никого не вытесняя.
 * Для тихой подстройки под аккаунт: иначе устройства одного аккаунта
 * сверх лимита вытесняли бы друг друга по очереди на каждом запросе.
 */
export async function linkDeviceIfRoom(
  db: D1Database, deviceId: string, entitlementId: string, maxDevices: number,
): Promise<boolean> {
  const result = await db.prepare(
    `UPDATE devices SET entitlement_id = ?1 WHERE id = ?2
       AND (SELECT COUNT(*) FROM devices WHERE entitlement_id = ?1 AND id != ?2) < ?3`,
  ).bind(entitlementId, deviceId, maxDevices).run();
  return (result.meta.changes ?? 0) > 0;
}

/**
 * Какой из двух доступов лучше: действующий лучше истёкшего, подписка
 * лучше промокода, дальний срок лучше ближнего. При равенстве — первый.
 */
export function better(
  a: Entitlement | null, b: Entitlement | null, now: number,
): Entitlement | null {
  const rank = (e: Entitlement | null) =>
    e ? [e.period_end > now ? 1 : 0, e.kind === "subscription" ? 1 : 0, e.period_end] : [-1, 0, 0];
  const [ra, rb] = [rank(a), rank(b)];
  for (let i = 0; i < ra.length; i++) {
    if (ra[i]! !== rb[i]!) return ra[i]! > rb[i]! ? a : b;
  }
  return a;
}
