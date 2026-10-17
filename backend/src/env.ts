import type { ClaudeLike } from "./claude";

/** Привязки и настройки Worker. Секреты задаются `wrangler secret put`. */
export interface Env {
  DB: D1Database;
  /**
   * Хранилище снимков бэкапа (R2, аналог S3, P-71). Не подключено — снимки
   * пишутся в D1 кусками, как до R2: сервер работает и без него.
   */
  BACKUPS?: R2Bucket;
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
  /** Потолок бесплатных вопросов помощнику на весь сервер за сутки. */
  HELP_DAILY_CAP?: string;
  /** Самая старая сборка приложения, которой сервер отвечает (P-71); пусто — все. */
  MIN_CLIENT_BUILD?: string;
  /**
   * Секрет служебных маршрутов `/v1/admin/*` (P-76): выгрузка и удаление
   * данных по коду поддержки, когда человек пишет, а не жмёт кнопку.
   * Нет секрета — маршрутов нет.
   */
  ADMIN_TOKEN?: string;
  /** Выключенные функции через запятую (`lesson,help` или `all`), см. compat.ts. */
  DISABLED_FEATURES?: string;
  /** Что сейчас развёрнуто — коммит из деплоя; видно в /v1/health. */
  BUILD_VERSION?: string;
  /**
   * Почта поддержки (P-72): привязка отправки писем Cloudflare, адрес
   * отправителя в своём домене и куда слать. Не заданы — обращения только в базе.
   */
  SUPPORT_MAIL?: SendEmail;
  SUPPORT_FROM?: string;
  SUPPORT_TO?: string;
}

/** Внешний мир, подменяемый в тестах: модель, сеть, часы и случайность. */
export interface Deps {
  claude: ClaudeLike;
  fetch: typeof fetch;
  /** Секунды Unix. */
  now: () => number;
  randomBytes: (count: number) => Uint8Array;
  /**
   * Дать работе дожить после ответа или обрыва связи (ExecutionContext.waitUntil).
   * Без неё свёрнутый телефон рвал соединение — и оплаченный вызов модели пропадал.
   */
  waitUntil?: (promise: Promise<unknown>) => void;
  /** Отправить письмо об обращении в поддержку; нет — письма не шлются. */
  sendSupportMail?: (mail: import("./support").SupportMail) => Promise<void>;
}

export function intVar(value: string | undefined, fallback: number): number {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}
