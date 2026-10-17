import { ApiError } from "./http";
import type { Env } from "./env";

/**
 * Совместимость сервера и приложений разных версий (P-71).
 *
 * Приложение из App Store обновляется не сразу и не у всех: у части людей
 * годами живёт старая версия. Поэтому сервер обязан понимать все версии,
 * которые ещё не отключены явно, а отключение — это решение, а не
 * побочный эффект деплоя. Правила — docs/server-updates.md.
 */

/** Версия формата API: меняется только с новым префиксом пути (/v2). */
export const API_VERSION = 1;

/** Сборка приложения из заголовка `x-recap-client: ios/0.4 (17)`; нет — null. */
export function clientBuild(request: Request): number | null {
  const header = request.headers.get("x-recap-client") ?? "";
  const match = /\((\d{1,9})\)\s*$/.exec(header);
  return match ? Number(match[1]) : null;
}

/**
 * Маршруты, которые работают для любой версии: здоровье сервера и права
 * человека на его данные (выгрузка, удаление, скачать свои копии). Старое
 * приложение не должно терять возможность забрать или стереть данные.
 */
const ALWAYS_ALLOWED = new Set([
  "GET /v1/health", "GET /v1/me", "DELETE /v1/me", "GET /v1/me/export", "DELETE /v1/account",
  "GET /v1/backups", "DELETE /v1/backups",
]);

/**
 * Слишком старое приложение получает 426 с понятной просьбой обновиться.
 * Без заголовка — пропускаем: так ходили все версии до появления проверки,
 * и среди них нет тех, что пора отключать.
 */
export function requireSupportedClient(request: Request, env: Env, route: string): void {
  const minimum = Number.parseInt(env.MIN_CLIENT_BUILD ?? "", 10);
  if (!Number.isFinite(minimum) || minimum <= 0) return;
  if (ALWAYS_ALLOWED.has(route) || route.startsWith("GET /v1/backups/")) return;
  const build = clientBuild(request);
  if (build !== null && build < minimum) throw new ApiError(426, "upgrade_required");
}

/** Какие функции можно выключить, не выпуская новую версию. */
const FEATURES: Record<string, string[]> = {
  deck: ["POST /v1/deck"],
  lesson: ["POST /v1/lesson"],
  discuss: ["POST /v1/discuss"],
  lesson_chat: ["POST /v1/lesson/chat"],
  help: ["POST /v1/help"],
  backups: ["POST /v1/backups"],
  promo: ["POST /v1/promo/redeem"],
  support: ["POST /v1/support"],
};

export function featureOf(route: string): string | null {
  for (const [feature, routes] of Object.entries(FEATURES)) {
    if (routes.includes(route)) return feature;
  }
  return null;
}

/**
 * Аварийный выключатель: `DISABLED_FEATURES = "lesson,help"` в переменных
 * Worker отвечает 503 на эти маршруты — например, когда модель сбоит или
 * расход вышел из-под контроля. Остальное работает; приложение показывает
 * «на обслуживании», а не ошибку.
 */
export function requireEnabled(env: Env, route: string): void {
  const feature = featureOf(route);
  if (!feature) return;
  const disabled = (env.DISABLED_FEATURES ?? "").split(",").map((item) => item.trim());
  if (disabled.includes(feature) || disabled.includes("all")) {
    throw new ApiError(503, "feature_disabled");
  }
}
