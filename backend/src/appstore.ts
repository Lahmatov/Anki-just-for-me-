import { ApiError } from "./http";
import { base64url, base64urlDecode } from "./crypto";
import type { Deps, Env } from "./env";
import type { VerifiedSubscription } from "./quota";

/**
 * Проверка подписки через App Store Server API.
 *
 * Клиенту не верим ни в чём: он присылает только номер транзакции, а статус,
 * товар и срок сервер спрашивает у Apple сам, по защищённому соединению,
 * подписав запрос своим ключом In-App Purchase. Подделать ответ Apple
 * взломанное приложение не может.
 */
const PRODUCTION = "https://api.storekit.itunes.apple.com";
const SANDBOX = "https://api.storekit-sandbox.itunes.apple.com";

/** Активна (1) или в льготном периоде после неудачного списания (4). */
const ACTIVE_STATUSES = new Set([1, 4]);

export async function verifySubscription(
  env: Env, deps: Deps, transactionId: string,
): Promise<VerifiedSubscription> {
  if (!env.APPSTORE_KEY_ID || !env.APPSTORE_ISSUER_ID || !env.APPSTORE_PRIVATE_KEY) {
    throw new ApiError(503, "subscriptions_not_configured");
  }
  if (!/^\d{1,32}$/.test(transactionId)) throw new ApiError(400, "invalid_field", "transactionId");

  const token = await appStoreJWT(env, deps.now());
  // Apple советует: сначала боевой сервер, при 404 — песочница (сборки
  // из TestFlight и Xcode покупают в песочнице).
  let response = await request(deps, PRODUCTION, transactionId, token);
  if (response.status === 404) response = await request(deps, SANDBOX, transactionId, token);
  if (response.status === 404) throw new ApiError(404, "subscription_not_found");
  if (!response.ok) throw new ApiError(502, "appstore_unavailable");

  const body = await response.json() as SubscriptionStatusResponse;
  if (body.bundleId !== env.BUNDLE_ID) throw new ApiError(403, "subscription_not_valid");

  const products = new Set(env.SUBSCRIPTION_PRODUCTS.split(",").map((item) => item.trim()));
  const now = deps.now();
  for (const group of body.data ?? []) {
    for (const last of group.lastTransactions ?? []) {
      if (!ACTIVE_STATUSES.has(last.status) || !last.signedTransactionInfo) continue;
      const info = decodeJWSPayload<TransactionInfo>(last.signedTransactionInfo);
      const expires = Math.floor((info.expiresDate ?? 0) / 1000);
      if (info.bundleId !== env.BUNDLE_ID || !products.has(info.productId)
          || info.revocationDate || expires <= now) {
        continue;
      }
      return {
        originalTransactionId: info.originalTransactionId,
        productId: info.productId,
        purchaseDate: Math.floor(info.purchaseDate / 1000),
        expiresDate: expires,
      };
    }
  }
  throw new ApiError(403, "subscription_not_active");
}

async function request(deps: Deps, host: string, transactionId: string, token: string) {
  return deps.fetch(`${host}/inApps/v1/subscriptions/${transactionId}`, {
    headers: { authorization: `Bearer ${token}` },
  });
}

/** JWT для App Store Server API: ES256, живёт 20 минут. */
export async function appStoreJWT(env: Env, now: number): Promise<string> {
  const header = { alg: "ES256", kid: env.APPSTORE_KEY_ID, typ: "JWT" };
  const payload = {
    iss: env.APPSTORE_ISSUER_ID, iat: now, exp: now + 1200,
    aud: "appstoreconnect-v1", bid: env.BUNDLE_ID,
  };
  const encoder = new TextEncoder();
  const signingInput = base64url(encoder.encode(JSON.stringify(header))) + "."
    + base64url(encoder.encode(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToDer(env.APPSTORE_PRIVATE_KEY ?? ""),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  // Web Crypto отдаёт подпись ECDSA сразу в виде r‖s — ровно как требует JWS.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(signingInput));
  return signingInput + "." + base64url(new Uint8Array(signature));
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const bytes = Uint8Array.from(atob(body), (char) => char.charCodeAt(0));
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

/**
 * Полезная нагрузка JWS из ответа Apple. Подпись здесь не проверяется
 * намеренно: ответ получен напрямую от Apple по TLS, это и есть гарантия.
 * JWS, присланный клиентом, так читать было бы нельзя.
 */
export function decodeJWSPayload<T>(jws: string): T {
  const part = jws.split(".")[1];
  if (!part) throw new ApiError(502, "appstore_unavailable");
  return JSON.parse(new TextDecoder().decode(base64urlDecode(part))) as T;
}

interface SubscriptionStatusResponse {
  bundleId?: string;
  data?: { lastTransactions?: { status: number; signedTransactionInfo?: string }[] }[];
}

interface TransactionInfo {
  originalTransactionId: string;
  productId: string;
  bundleId: string;
  purchaseDate: number;
  expiresDate?: number;
  revocationDate?: number;
}
