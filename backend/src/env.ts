import type { ClaudeLike } from "./claude";

/** Привязки и настройки Worker. Секреты задаются `wrangler secret put`. */
export interface Env {
  DB: D1Database;
  /** Секрет: ключ Anthropic. Живёт только здесь — в приложении его нет. */
  ANTHROPIC_API_KEY: string;
  /** Секрет: «перец» для хешей промокодов и IP. */
  PROMO_PEPPER: string;
  /** Секреты App Store Server API (ключ In-App Purchase из App Store Connect). */
  APPSTORE_KEY_ID?: string;
  APPSTORE_ISSUER_ID?: string;
  APPSTORE_PRIVATE_KEY?: string;
  /**
   * Секреты входа через Apple: Team ID и ключ Sign in with Apple (.p8).
   * Нужны, чтобы обменять код входа на токен и отозвать его при удалении
   * аккаунта. Не заданы — вход выключен (503), остальное работает.
   */
  APPLE_TEAM_ID?: string;
  SIWA_KEY_ID?: string;
  SIWA_PRIVATE_KEY?: string;

  BUNDLE_ID: string;
  MODEL: string;
  SUBSCRIPTION_UNITS: string;
  PROMO_UNITS: string;
  MAX_DEVICES_PER_SUBSCRIPTION: string;
  SUBSCRIPTION_PRODUCTS: string;
}

/** Внешний мир, подменяемый в тестах: модель, сеть, часы и случайность. */
export interface Deps {
  claude: ClaudeLike;
  fetch: typeof fetch;
  /** Секунды Unix. */
  now: () => number;
  randomBytes: (count: number) => Uint8Array;
}

export function intVar(value: string | undefined, fallback: number): number {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}
