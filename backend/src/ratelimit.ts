import { ApiError } from "./http";

/**
 * Ограничение частоты: окно фиксированной длины на ключ, одним атомарным
 * запросом. Защищает и кошелёк (запросы к ИИ), и промокоды (перебор).
 */
export async function hit(
  db: D1Database, key: string, limit: number, windowSeconds: number, now: number,
): Promise<void> {
  const window = Math.floor(now / windowSeconds);
  const row = await db.prepare(
    `INSERT INTO rate_limits (key, win, count, expires_at) VALUES (?, ?, 1, ?)
     ON CONFLICT(key) DO UPDATE SET
       count = CASE WHEN win = excluded.win THEN count + 1 ELSE 1 END,
       win = excluded.win,
       expires_at = excluded.expires_at
     RETURNING count`,
  ).bind(key, window, (window + 1) * windowSeconds).first<{ count: number }>();
  if ((row?.count ?? 0) > limit) throw new ApiError(429, "rate_limited");
}
