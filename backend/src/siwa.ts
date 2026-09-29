import { ApiError } from "./http";
import { base64urlDecode, es256JWT, sha256Hex } from "./crypto";
import type { Deps, Env } from "./env";

/**
 * Вход через Apple (Sign in with Apple).
 *
 * Приложение присылает три вещи: identity token (JWT от Apple), одноразовый
 * код авторизации и «сырой» nonce. Сервер:
 * 1. проверяет подпись токена открытым ключом Apple, издателя, получателя
 *    (наш Bundle ID), срок и nonce — чужой, старый или перехваченный токен
 *    не пройдёт;
 * 2. меняет код на refresh token у самой Apple — он нужен, чтобы при
 *    удалении аккаунта отозвать вход (требование App Store с 2022 года).
 *    Ответ Apple при этом должен быть о том же человеке, что и токен.
 */
const ISSUER = "https://appleid.apple.com";
const KEYS_URL = "https://appleid.apple.com/auth/keys";
const TOKEN_URL = "https://appleid.apple.com/auth/token";
const REVOKE_URL = "https://appleid.apple.com/auth/revoke";

/** Часы телефона и сервера расходятся — пять минут на это. */
const CLOCK_SKEW = 300;

export interface AppleClaims {
  sub: string;
}

export function siwaConfigured(env: Env): boolean {
  return Boolean(env.APPLE_TEAM_ID && env.SIWA_KEY_ID && env.SIWA_PRIVATE_KEY);
}

export async function verifyIdentityToken(
  deps: Deps, token: string, bundleId: string, rawNonce: string,
): Promise<AppleClaims> {
  const invalid = () => new ApiError(401, "invalid_identity_token");
  const parts = token.split(".");
  if (parts.length !== 3) throw invalid();
  const [headerPart, payloadPart, signaturePart] = parts as [string, string, string];

  let header: { alg?: string; kid?: string };
  let claims: {
    iss?: string; aud?: string | string[]; exp?: number; iat?: number; sub?: string; nonce?: string;
  };
  try {
    header = JSON.parse(new TextDecoder().decode(base64urlDecode(headerPart)));
    claims = JSON.parse(new TextDecoder().decode(base64urlDecode(payloadPart)));
  } catch {
    throw invalid();
  }
  // Только RS256: «alg: none» и подмена алгоритма — классические атаки на JWT.
  if (header.alg !== "RS256" || !header.kid) throw invalid();

  const key = await appleKey(deps, header.kid);
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5", key, base64urlDecode(signaturePart),
    new TextEncoder().encode(`${headerPart}.${payloadPart}`));
  if (!valid) throw invalid();

  const now = deps.now();
  const audience = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (claims.iss !== ISSUER || !audience.includes(bundleId)) throw invalid();
  if (typeof claims.exp !== "number" || claims.exp + CLOCK_SKEW <= now) throw invalid();
  if (typeof claims.iat === "number" && claims.iat - CLOCK_SKEW > now) throw invalid();
  if (typeof claims.sub !== "string" || claims.sub.length === 0 || claims.sub.length > 255) {
    throw invalid();
  }
  // В запрос ко входу приложение кладёт SHA-256 от nonce, а серверу шлёт
  // сам nonce: токен, выданный для другого запроса, не подойдёт.
  if (claims.nonce !== await sha256Hex(rawNonce)) throw invalid();
  return { sub: claims.sub };
}

async function appleKey(deps: Deps, kid: string): Promise<CryptoKey> {
  let response: Response;
  try {
    response = await deps.fetch(KEYS_URL);
  } catch {
    throw new ApiError(502, "apple_unavailable");
  }
  if (!response.ok) throw new ApiError(502, "apple_unavailable");
  const body = await response.json() as { keys?: (JsonWebKey & { kid?: string })[] };
  const jwk = body.keys?.find((key) => key.kid === kid && key.kty === "RSA");
  if (!jwk?.n || !jwk.e) throw new ApiError(401, "invalid_identity_token");
  return crypto.subtle.importKey(
    "jwk", { kty: "RSA", n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
}

/** Секрет клиента для запросов к Apple: JWT, подписанный ключом Sign in with Apple. */
export async function clientSecret(env: Env, now: number): Promise<string> {
  return es256JWT(env.SIWA_PRIVATE_KEY ?? "", { kid: env.SIWA_KEY_ID }, {
    iss: env.APPLE_TEAM_ID, iat: now, exp: now + 300, aud: ISSUER, sub: env.BUNDLE_ID,
  });
}

/**
 * Код авторизации → refresh token. Код одноразовый и живёт пять минут,
 * поэтому обмен идёт сразу при входе.
 */
export async function exchangeCode(env: Env, deps: Deps, code: string, sub: string): Promise<string> {
  const form = new URLSearchParams({
    client_id: env.BUNDLE_ID,
    client_secret: await clientSecret(env, deps.now()),
    code,
    grant_type: "authorization_code",
  });
  let response: Response;
  try {
    response = await deps.fetch(TOKEN_URL, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: form.toString(),
    });
  } catch {
    throw new ApiError(502, "apple_unavailable");
  }
  if (response.status === 400) throw new ApiError(400, "invalid_authorization_code");
  if (!response.ok) throw new ApiError(502, "apple_unavailable");
  const body = await response.json() as { refresh_token?: string; id_token?: string };
  if (!body.refresh_token || !body.id_token) throw new ApiError(502, "apple_unavailable");
  // id_token получен прямо от Apple по TLS — подпись не нужна. Сверяем
  // человека: чужой код к своему токену не приложить.
  const payload = body.id_token.split(".")[1];
  let idSub: unknown;
  try {
    idSub = payload ? JSON.parse(new TextDecoder().decode(base64urlDecode(payload))).sub : undefined;
  } catch {
    idSub = undefined;
  }
  if (idSub !== sub) throw new ApiError(401, "invalid_identity_token");
  return body.refresh_token;
}

/**
 * Отозвать вход у Apple. Токен, который Apple уже не знает (человек сам
 * отключил приложение в настройках Apple ID), — тоже успех: отзывать нечего.
 */
export async function revokeToken(env: Env, deps: Deps, refreshToken: string): Promise<void> {
  const form = new URLSearchParams({
    client_id: env.BUNDLE_ID,
    client_secret: await clientSecret(env, deps.now()),
    token: refreshToken,
    token_type_hint: "refresh_token",
  });
  let response: Response;
  try {
    response = await deps.fetch(REVOKE_URL, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: form.toString(),
    });
  } catch {
    throw new ApiError(502, "apple_unavailable");
  }
  if (response.ok || response.status === 400) return;
  throw new ApiError(502, "apple_unavailable");
}
