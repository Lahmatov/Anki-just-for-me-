import { RESERVATION_TTL } from "./quota";

/**
 * Сроки хранения (GDPR, ст. 5(1)(e): данные не держат дольше, чем нужно).
 * Те же числа — в политике конфиденциальности; меняя здесь, поменять и там.
 */
export const RETENTION = {
  /** Устройство, год не выходившее на связь, забывается целиком. */
  inactiveDeviceDays: 365,
  /** Журнал расхода нужен, чтобы видеть стоимость по месяцам, — три месяца хватает. */
  usageLogDays: 90,
  /**
   * Подписка без устройств после конца оплаченного срока. Покупка
   * при этом не теряется: «Восстановить покупки» заново спросит Apple.
   */
  lapsedSubscriptionDays: 30,
  /** Кеш описаний серий из TVMaze: он и так обновляется через неделю. */
  episodeCacheDays: 30,
} as const;

const DAY = 86_400;

export interface PurgeReport {
  devices: number;
  accounts: number;
  usageLog: number;
  entitlements: number;
  rateLimits: number;
  reservations: number;
  episodeCache: number;
}

/**
 * Ночная чистка — запускается по расписанию (`[triggers]` в wrangler.toml).
 * Одним пакетом: либо всё, либо ничего, чтобы не остались записи
 * о сериях и расходе без самого устройства.
 */
export async function purge(db: D1Database, now: number): Promise<PurgeReport> {
  const deviceCutoff = now - RETENTION.inactiveDeviceDays * DAY;
  const stale = "SELECT id FROM devices WHERE last_seen_at < ?";
  const results = await db.batch([
    db.prepare(`DELETE FROM device_episodes WHERE device_id IN (${stale})`).bind(deviceCutoff),
    db.prepare(`DELETE FROM usage_log WHERE created_at < ? OR device_id IN (${stale})`)
      .bind(now - RETENTION.usageLogDays * DAY, deviceCutoff),
    db.prepare(`UPDATE promo_codes SET redeemed_by = NULL WHERE redeemed_by IN (${stale})`)
      .bind(deviceCutoff),
    db.prepare("DELETE FROM devices WHERE last_seen_at < ?").bind(deviceCutoff),
    // Аккаунт без единого телефона, год не входивший. Отозвать вход у Apple
    // здесь не нужно: это требуется, когда удалить просит сам человек.
    db.prepare(
      `DELETE FROM accounts WHERE last_seen_at < ?
         AND NOT EXISTS (SELECT 1 FROM devices WHERE devices.account_id = accounts.id)`,
    ).bind(deviceCutoff),
    // Доступ без единого устройства и аккаунта: промо — сразу (код
    // одноразовый, вернуть его на другой телефон нельзя), подписка — через
    // месяц после конца срока. Свежие записи не трогаем: гашение кода
    // создаёт доступ раньше, чем привязывает к нему устройство.
    db.prepare(
      `DELETE FROM entitlements
       WHERE NOT EXISTS (SELECT 1 FROM devices WHERE devices.entitlement_id = entitlements.id)
         AND NOT EXISTS (SELECT 1 FROM accounts WHERE accounts.entitlement_id = entitlements.id)
         AND updated_at < ?
         AND (kind = 'promo' OR period_end < ?)`,
    ).bind(now - DAY, now - RETENTION.lapsedSubscriptionDays * DAY),
    db.prepare("DELETE FROM rate_limits WHERE expires_at < ?").bind(now),
    db.prepare("DELETE FROM reservations WHERE created_at < ?").bind(now - RESERVATION_TTL),
    db.prepare("DELETE FROM episode_cache WHERE fetched_at < ?")
      .bind(now - RETENTION.episodeCacheDays * DAY),
  ]);
  const changes = (index: number) => results[index]?.meta?.changes ?? 0;
  return {
    devices: changes(3),
    accounts: changes(4),
    usageLog: changes(1),
    entitlements: changes(5),
    rateLimits: changes(6),
    reservations: changes(7),
    episodeCache: changes(8),
  };
}
