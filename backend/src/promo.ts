import { ApiError } from "./http";
import { CROCKFORD, hmacHex } from "./crypto";

/**
 * Промокоды вида RECAP-XXXX-XXXX-XXXX-XXXX: 16 символов Crockford, 80 бит
 * случайности — перебрать нельзя даже без ограничения частоты.
 *
 * В базе лежит только HMAC-SHA256 кода с секретным перцем. Украденная база
 * кодов не даёт: без перца (он в секретах Worker) хеш не проверить,
 * а сам код из хеша не восстановить.
 */
export const CODE_LENGTH = 16;
export const CODE_PREFIX = "RECAP";

/** Приводит ввод человека к каноническому виду: регистр, дефисы, пробелы,
 *  похожие буквы (O → 0, I и L → 1). Невозможный код — null. */
export function normalizeCode(input: string): string | null {
  let text = input.toUpperCase().replace(/[\s-]/g, "");
  if (text.startsWith(CODE_PREFIX)) text = text.slice(CODE_PREFIX.length);
  text = text.replace(/O/g, "0").replace(/[IL]/g, "1");
  if (text.length !== CODE_LENGTH) return null;
  for (const char of text) {
    if (!CROCKFORD.includes(char)) return null;
  }
  return text;
}

export function formatCode(normalized: string): string {
  const groups = normalized.match(/.{4}/g) ?? [];
  return [CODE_PREFIX, ...groups].join("-");
}

export async function codeHash(pepper: string, normalized: string): Promise<string> {
  if (!pepper || pepper.length < 32) throw new ApiError(503, "promo_not_configured");
  return hmacHex(pepper, "promo:" + normalized);
}

export interface PromoGrant {
  days: number;
  units: number;
}

/**
 * Погасить код: один атомарный UPDATE с условием «ещё не погашен и не истёк».
 * Два устройства с одним кодом одновременно не пройдут оба.
 */
export async function redeem(
  db: D1Database, pepper: string, input: string, deviceId: string, now: number,
): Promise<PromoGrant> {
  const normalized = normalizeCode(input);
  if (!normalized) throw new ApiError(400, "invalid_code");
  const hash = await codeHash(pepper, normalized);
  const row = await db.prepare(
    `UPDATE promo_codes SET redeemed_at = ?1, redeemed_by = ?2
     WHERE hash = ?3 AND redeemed_at IS NULL AND (expires_at IS NULL OR expires_at > ?1)
     RETURNING days, units`,
  ).bind(now, deviceId, hash).first<PromoGrant>();
  // Один ответ на «нет такого», «уже погашен» и «истёк»: перебирающий
  // не должен узнавать, какие коды существуют.
  if (!row) throw new ApiError(404, "code_not_valid");
  return row;
}
