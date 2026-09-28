import { describe, expect, it } from "vitest";
import { makeWorld } from "./helpers";
import { appStoreJWT } from "../src/appstore";
import { base64url, base64urlDecode } from "../src/crypto";

async function keyPair() {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer);
  let binary = "";
  for (const byte of der) binary += String.fromCharCode(byte);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----`;
  return { pem, publicKey: pair.publicKey };
}

/** JWS в том виде, в каком его отдаёт Apple: нас интересует только payload. */
function jws(payload: object): string {
  const encode = (value: object) => base64url(new TextEncoder().encode(JSON.stringify(value)));
  return `${encode({ alg: "ES256" })}.${encode(payload)}.signature`;
}

function appleResponse(overrides: Record<string, unknown> = {}, status = 1, bundleId = "com.lahmatov.ajfm") {
  const now = 1_800_000_000;
  return () => Response.json({
    bundleId,
    data: [{ lastTransactions: [{
      status,
      signedTransactionInfo: jws({
        originalTransactionId: "2000000111", productId: "com.lahmatov.ajfm.plus.monthly",
        bundleId: "com.lahmatov.ajfm", purchaseDate: (now - 86_400) * 1000,
        expiresDate: (now + 29 * 86_400) * 1000, ...overrides,
      }),
    }] }],
  });
}

async function world(apple: () => Response, sandbox?: () => Response) {
  const routes: Record<string, () => Response> = {
    "https://api.storekit.itunes.apple.com/": apple,
  };
  if (sandbox) routes["https://api.storekit-sandbox.itunes.apple.com/"] = sandbox;
  const w = makeWorld({ routes });
  const { pem } = await keyPair();
  w.env.APPSTORE_KEY_ID = "KEY123";
  w.env.APPSTORE_ISSUER_ID = "issuer-uuid";
  w.env.APPSTORE_PRIVATE_KEY = pem;
  return w;
}

describe("подписка", () => {
  it("JWT для Apple подписан ES256 и проверяется открытым ключом", async () => {
    const { pem, publicKey } = await keyPair();
    const env = { APPSTORE_KEY_ID: "K", APPSTORE_ISSUER_ID: "I", APPSTORE_PRIVATE_KEY: pem,
                  BUNDLE_ID: "com.lahmatov.ajfm" } as never;
    const token = await appStoreJWT(env, 1_800_000_000);
    const [header, payload, signature] = token.split(".");
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" }, publicKey, base64urlDecode(signature!),
      new TextEncoder().encode(`${header}.${payload}`));
    expect(valid).toBe(true);
    const claims = JSON.parse(new TextDecoder().decode(base64urlDecode(payload!)));
    expect(claims).toMatchObject({ aud: "appstoreconnect-v1", bid: "com.lahmatov.ajfm", iss: "I" });
    expect(claims.exp - claims.iat).toBeLessThanOrEqual(3600);
  });

  it("активная подписка даёт доступ", async () => {
    const w = await world(appleResponse());
    const token = await w.device();
    const response = await w.call("POST", "/v1/subscription/verify", { transactionId: "2000000111" }, token);
    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ plan: "subscription", active: true, unitsTotal: 2_000_000 });
  });

  it("покупка из песочницы находится после 404 боевого сервера", async () => {
    const w = await world(() => new Response("", { status: 404 }), appleResponse());
    const token = await w.device();
    expect((await w.call("POST", "/v1/subscription/verify", { transactionId: "1" }, token)).status).toBe(200);
  });

  it("чужое приложение, чужой товар, истёкшая и отозванная — отказ", async () => {
    for (const apple of [
      appleResponse({}, 1, "com.other.app"),
      appleResponse({ productId: "com.lahmatov.ajfm.coins" }),
      appleResponse({}, 2),
      appleResponse({ expiresDate: 1_700_000_000_000 }),
      appleResponse({ revocationDate: 1_799_000_000_000 }),
    ]) {
      const w = await world(apple);
      const token = await w.device();
      const response = await w.call("POST", "/v1/subscription/verify", { transactionId: "5" }, token);
      expect(response.status).toBe(403);
      expect((await w.call("GET", "/v1/me", undefined, token)).body.plan).toBe("none");
    }
  });

  it("номер транзакции проверяется до запроса к Apple", async () => {
    const w = await world(appleResponse());
    const token = await w.device();
    const response = await w.call("POST", "/v1/subscription/verify", { transactionId: "../../x" }, token);
    expect(response.status).toBe(400);
  });

  it("без ключей App Store подписка честно недоступна", async () => {
    const w = makeWorld();
    const token = await w.device();
    const response = await w.call("POST", "/v1/subscription/verify", { transactionId: "1" }, token);
    expect(response.status).toBe(503);
    expect(response.body.error).toBe("subscriptions_not_configured");
  });

  it("одна покупка — общий лимит и не больше двух устройств", async () => {
    const w = await world(appleResponse());
    const first = await w.device();
    await w.call("POST", "/v1/subscription/verify", { transactionId: "1" }, first);
    w.advance(10);
    const second = await w.device();
    await w.call("POST", "/v1/subscription/verify", { transactionId: "1" }, second);
    w.advance(3_700);
    // Второе устройство активно, первое молчит — третье вытесняет первое.
    await w.call("GET", "/v1/me", undefined, second);
    const third = await w.device();
    await w.call("POST", "/v1/subscription/verify", { transactionId: "1" }, third);

    expect((await w.call("GET", "/v1/me", undefined, first)).body.plan).toBe("none");
    expect((await w.call("GET", "/v1/me", undefined, second)).body.plan).toBe("subscription");
    expect((await w.call("GET", "/v1/me", undefined, third)).body.plan).toBe("subscription");
    expect(w.db.raw.prepare("SELECT COUNT(*) AS n FROM entitlements").get()).toEqual({ n: 1 });
  });

  it("продление обнуляет счётчик периода", async () => {
    let expires = (1_800_000_000 + 29 * 86_400) * 1000;
    const w = await world(() => appleResponse({ expiresDate: expires })());
    const token = await w.device();
    await w.call("POST", "/v1/subscription/verify", { transactionId: "1" }, token);
    w.db.raw.prepare("UPDATE entitlements SET used = 500000").run();
    expires += 30 * 86_400_000;
    const renewed = await w.call("POST", "/v1/subscription/verify", { transactionId: "1" }, token);
    expect(renewed.body.unitsLeft).toBe(2_000_000);
  });
});
