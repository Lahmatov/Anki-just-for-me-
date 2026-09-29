import { describe, expect, it } from "vitest";
import { CODE, DECK_REQUEST, makeWorld } from "./helpers";
import { base64url, open, seal, sha256Hex } from "../src/crypto";
import { better, type Entitlement } from "../src/quota";
import { purge, RETENTION } from "../src/retention";

const BUNDLE = "com.lahmatov.ajfm";
const DAY = 86_400;
const encode = (value: object) => base64url(new TextEncoder().encode(JSON.stringify(value)));

async function ecPem(): Promise<string> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer);
  let binary = "";
  for (const byte of der) binary += String.fromCharCode(byte);
  return `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----`;
}

async function rsaPair(): Promise<CryptoKeyPair> {
  return await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
}

/**
 * Мир, где Apple — подделка под нашим контролем: свой ключ подписи
 * identity token, свой обмен кода и отзыв токенов.
 */
async function appleWorld() {
  const apple = await rsaPair();
  const jwk = await crypto.subtle.exportKey("jwk", apple.publicKey);
  const state = {
    exchanged: [] as string[],
    revoked: [] as string[],
    tokenStatus: 200,
    revokeStatus: 200,
  };
  const world = makeWorld({ routes: {
    "https://appleid.apple.com/auth/keys": () =>
      Response.json({ keys: [{ ...jwk, kid: "K1", alg: "RS256", use: "sig" }] }),
    "https://appleid.apple.com/auth/token": (init) => {
      const form = new URLSearchParams(String(init?.body ?? ""));
      const code = form.get("code") ?? "";
      state.exchanged.push(code);
      if (state.tokenStatus !== 200) {
        return Response.json({ error: "invalid_grant" }, { status: state.tokenStatus });
      }
      // Код вида «code-<sub>» — Apple вернёт id_token именно этого человека.
      const sub = code.replace(/^code-/, "");
      return Response.json({
        access_token: "at", refresh_token: `rt-${sub}`,
        id_token: `${encode({ alg: "RS256" })}.${encode({ sub })}.sig`,
      });
    },
    "https://appleid.apple.com/auth/revoke": (init) => {
      state.revoked.push(new URLSearchParams(String(init?.body ?? "")).get("token") ?? "");
      return new Response("", { status: state.revokeStatus });
    },
  } });
  world.env.APPLE_TEAM_ID = "TEAM123";
  world.env.SIWA_KEY_ID = "SIWA456";
  world.env.SIWA_PRIVATE_KEY = await ecPem();

  async function identityToken(sub: string, options: {
    claims?: Record<string, unknown>; header?: Record<string, unknown>; key?: CryptoKey; nonce?: string;
  } = {}) {
    const header = encode({ alg: "RS256", kid: "K1", ...options.header });
    const payload = encode({
      iss: "https://appleid.apple.com", aud: BUNDLE, sub,
      iat: world.now(), exp: world.now() + 600,
      nonce: await sha256Hex(options.nonce ?? "nonce-1"),
      ...options.claims,
    });
    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5", options.key ?? apple.privateKey,
      new TextEncoder().encode(`${header}.${payload}`));
    return `${header}.${payload}.${base64url(new Uint8Array(signature))}`;
  }

  async function signIn(token: string, sub = "apple-user-1", code = `code-${sub}`) {
    return world.call("POST", "/v1/account/apple", {
      identityToken: await identityToken(sub), authorizationCode: code, nonce: "nonce-1",
    }, token);
  }

  const count = (table: string) =>
    (world.db.raw.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number }).n;

  return { ...world, state, identityToken, signIn, count };
}

describe("вход через Apple", () => {
  it("создаёт аккаунт и отмечает телефон вошедшим", async () => {
    const w = await appleWorld();
    const token = await w.device();
    const response = await w.signIn(token);
    expect(response.status).toBe(200);
    expect(response.body.signedIn).toBe(true);
    expect((await w.call("GET", "/v1/me", undefined, token)).body.signedIn).toBe(true);
    expect(w.count("accounts")).toBe(1);
  });

  it("отдаёт код поддержки в статусе профиля, и он не раскрывает токен", async () => {
    const w = await appleWorld();
    const token = await w.device();
    const body = (await w.call("GET", "/v1/me", undefined, token)).body;
    expect(body.supportCode).toMatch(/^[0-9A-F]{4}-[0-9A-F]{4}$/);
    expect(token).not.toContain(body.supportCode.replace("-", "").toLowerCase());
    expect(body.signedIn).toBe(false);
  });

  it("хранит ни номер Apple, ни refresh token открытым текстом", async () => {
    const w = await appleWorld();
    await w.signIn(await w.device(), "apple-user-secret");
    const row = w.db.raw.prepare("SELECT * FROM accounts").get() as Record<string, string>;
    const dump = JSON.stringify(row);
    expect(dump).not.toContain("apple-user-secret");
    expect(dump).not.toContain("rt-apple-user-secret");
  });

  it("тот же Apple ID на втором телефоне попадает в тот же аккаунт", async () => {
    const w = await appleWorld();
    await w.signIn(await w.device());
    await w.signIn(await w.device());
    expect(w.count("accounts")).toBe(1);
  });

  it("обменивает код авторизации у Apple", async () => {
    const w = await appleWorld();
    await w.signIn(await w.device(), "u1");
    expect(w.state.exchanged).toEqual(["code-u1"]);
  });

  const forged: [string, (w: Awaited<ReturnType<typeof appleWorld>>) => Promise<string>][] = [
    ["чужой ключ подписи", async (w) => w.identityToken("u1", { key: (await rsaPair()).privateKey })],
    ["другое приложение", (w) => w.identityToken("u1", { claims: { aud: "com.other.app" } })],
    ["не Apple выдал", (w) => w.identityToken("u1", { claims: { iss: "https://evil.example" } })],
    ["просроченный", (w) => w.identityToken("u1", { claims: { exp: w.now() - 3600 } })],
    ["из будущего", (w) => w.identityToken("u1", { claims: { iat: w.now() + 3600 } })],
    ["другой nonce", (w) => w.identityToken("u1", { nonce: "someone-elses-nonce" })],
    ["алгоритм не RS256", (w) => w.identityToken("u1", { header: { alg: "HS256" } })],
    ["неизвестный ключ", (w) => w.identityToken("u1", { header: { kid: "K9" } })],
    ["пустой sub", (w) => w.identityToken("", {})],
  ];
  for (const [name, make] of forged) {
    it(`отклоняет токен: ${name}`, async () => {
      const w = await appleWorld();
      const response = await w.call("POST", "/v1/account/apple", {
        identityToken: await make(w), authorizationCode: "code-u1", nonce: "nonce-1",
      }, await w.device());
      expect(response.status).toBe(401);
      expect(response.body.error).toBe("invalid_identity_token");
      expect(w.count("accounts")).toBe(0);
    });
  }

  it("отклоняет «alg: none» без подписи", async () => {
    const w = await appleWorld();
    const unsigned = `${encode({ alg: "none", kid: "K1" })}.${encode({
      iss: "https://appleid.apple.com", aud: BUNDLE, sub: "u1", exp: w.now() + 600,
      nonce: await sha256Hex("nonce-1") })}.`;
    const response = await w.call("POST", "/v1/account/apple", {
      identityToken: unsigned, authorizationCode: "code-u1", nonce: "nonce-1" }, await w.device());
    expect(response.status).toBe(401);
  });

  it("не принимает код авторизации другого человека", async () => {
    const w = await appleWorld();
    const response = await w.signIn(await w.device(), "u1", "code-u2");
    expect(response.status).toBe(401);
    expect(w.count("accounts")).toBe(0);
  });

  it("говорит о негодном коде, если Apple его не принял", async () => {
    const w = await appleWorld();
    w.state.tokenStatus = 400;
    const response = await w.signIn(await w.device());
    expect(response.status).toBe(400);
    expect(response.body.error).toBe("invalid_authorization_code");
  });

  it("без ключа Sign in with Apple вход выключен, а не сломан", async () => {
    const w = await appleWorld();
    w.env.SIWA_PRIVATE_KEY = undefined;
    const response = await w.signIn(await w.device());
    expect(response.status).toBe(503);
    expect(response.body.error).toBe("signin_not_configured");
  });

  it("ограничивает частоту попыток входа", async () => {
    const w = await appleWorld();
    const token = await w.device();
    for (let i = 0; i < 10; i++) await w.signIn(token);
    expect((await w.signIn(token)).status).toBe(429);
  });
});

describe("доступ аккаунта на нескольких телефонах", () => {
  it("промокод с одного телефона работает на втором после входа", async () => {
    const w = await appleWorld();
    const a = await w.device();
    await w.signIn(a);
    await w.addPromo(CODE);
    await w.call("POST", "/v1/promo/redeem", { code: CODE }, a);

    const b = await w.device();
    const response = await w.signIn(b);
    expect(response.body.plan).toBe("promo");
    expect(response.body.active).toBe(true);
  });

  it("промокод, погашенный до входа, переходит в аккаунт", async () => {
    const w = await appleWorld();
    const a = await w.device();
    await w.addPromo(CODE);
    await w.call("POST", "/v1/promo/redeem", { code: CODE }, a);
    await w.signIn(a);

    const b = await w.device();
    expect((await w.signIn(b)).body.active).toBe(true);
  });

  it("доступ, полученный позже, доходит до другого телефона сам", async () => {
    const w = await appleWorld();
    const a = await w.device();
    const b = await w.device();
    await w.signIn(a);
    await w.signIn(b);
    await w.addPromo(CODE);
    await w.call("POST", "/v1/promo/redeem", { code: CODE }, a);
    expect((await w.call("GET", "/v1/me", undefined, b)).body.active).toBe(true);
  });

  it("тихая подстройка не превышает лимит устройств", async () => {
    const w = await appleWorld();                 // в тестах лимит — 2 устройства
    const [a, b, c] = [await w.device(), await w.device(), await w.device()];
    for (const token of [a, b, c]) await w.signIn(token);
    await w.addPromo(CODE);
    await w.call("POST", "/v1/promo/redeem", { code: CODE }, a);
    expect((await w.call("GET", "/v1/me", undefined, b)).body.active).toBe(true);
    expect((await w.call("GET", "/v1/me", undefined, c)).body.active).toBe(false);
    // И повторный запрос не вытесняет никого по кругу.
    expect((await w.call("GET", "/v1/me", undefined, b)).body.active).toBe(true);
  });

  it("выход забирает доступ аккаунта только с этого телефона", async () => {
    const w = await appleWorld();
    const a = await w.device();
    const b = await w.device();
    await w.signIn(a);
    await w.addPromo(CODE);
    await w.call("POST", "/v1/promo/redeem", { code: CODE }, a);
    await w.signIn(b);

    const out = await w.call("POST", "/v1/account/logout", {}, b);
    expect(out.body.signedIn).toBe(false);
    expect(out.body.active).toBe(false);
    expect((await w.call("GET", "/v1/me", undefined, b)).body.active).toBe(false);
    expect((await w.call("GET", "/v1/me", undefined, a)).body.active).toBe(true);
  });

  it("повторный вход возвращает доступ", async () => {
    const w = await appleWorld();
    const a = await w.device();
    await w.signIn(a);
    await w.addPromo(CODE);
    await w.call("POST", "/v1/promo/redeem", { code: CODE }, a);
    await w.call("POST", "/v1/account/logout", {}, a);
    expect((await w.signIn(a)).body.active).toBe(true);
  });

  it("выход без входа ничего не ломает", async () => {
    const w = await appleWorld();
    const response = await w.call("POST", "/v1/account/logout", {}, await w.device());
    expect(response.status).toBe(200);
    expect(response.body.signedIn).toBe(false);
  });

  it("«удалить устройство» не забирает промокод аккаунта у других телефонов", async () => {
    const w = await appleWorld();
    const a = await w.device();
    const b = await w.device();
    await w.signIn(a);
    await w.addPromo(CODE);
    await w.call("POST", "/v1/promo/redeem", { code: CODE }, a);
    await w.signIn(b);
    await w.call("DELETE", "/v1/me", undefined, a);
    expect((await w.call("GET", "/v1/me", undefined, b)).body.active).toBe(true);
  });
});

describe("удаление аккаунта", () => {
  it("отзывает вход у Apple и стирает аккаунт", async () => {
    const w = await appleWorld();
    const a = await w.device();
    await w.signIn(a, "u7");
    const response = await w.call("DELETE", "/v1/account", undefined, a);
    expect(response.status).toBe(200);
    expect(response.body.signedIn).toBe(false);
    expect(w.state.revoked).toEqual(["rt-u7"]);
    expect(w.count("accounts")).toBe(0);
  });

  it("забирает промо-доступ аккаунта со всех телефонов", async () => {
    const w = await appleWorld();
    const a = await w.device();
    const b = await w.device();
    await w.signIn(a);
    await w.addPromo(CODE);
    await w.call("POST", "/v1/promo/redeem", { code: CODE }, a);
    await w.signIn(b);
    await w.call("DELETE", "/v1/account", undefined, a);
    expect((await w.call("GET", "/v1/me", undefined, b)).body).toMatchObject({ active: false, signedIn: false });
    expect(w.count("entitlements")).toBe(0);
  });

  it("если Apple недоступен, не удаляет ничего и просит повторить", async () => {
    const w = await appleWorld();
    const a = await w.device();
    await w.signIn(a);
    w.state.revokeStatus = 503;
    const response = await w.call("DELETE", "/v1/account", undefined, a);
    expect(response.status).toBe(502);
    expect(response.body.error).toBe("apple_unavailable");
    expect(w.count("accounts")).toBe(1);
  });

  it("токен, который Apple уже не знает, не мешает удалению", async () => {
    const w = await appleWorld();
    const a = await w.device();
    await w.signIn(a);
    w.state.revokeStatus = 400;
    expect((await w.call("DELETE", "/v1/account", undefined, a)).status).toBe(200);
    expect(w.count("accounts")).toBe(0);
  });

  it("без входа удалять нечего", async () => {
    const w = await appleWorld();
    const response = await w.call("DELETE", "/v1/account", undefined, await w.device());
    expect(response.status).toBe(409);
    expect(response.body.error).toBe("not_signed_in");
  });
});

describe("мои данные на сервере", () => {
  it("отдаёт серии, расход и код поддержки без содержимого запросов", async () => {
    const w = await appleWorld();
    const token = await w.device();
    await w.addPromo(CODE);
    await w.call("POST", "/v1/promo/redeem", { code: CODE }, token);
    await w.call("POST", "/v1/deck", { ...DECK_REQUEST, subtitles: "SECRET SUBTITLE LINE" }, token);
    await w.signIn(token);

    const response = await w.call("GET", "/v1/me/export", undefined, token);
    expect(response.status).toBe(200);
    expect(response.body.supportCode).toMatch(/^[0-9A-F]{4}-[0-9A-F]{4}$/);
    expect(response.body.episodes).toEqual([
      expect.objectContaining({ showId: 431, season: 1, episode: 3 })]);
    expect(response.body.usage).toHaveLength(1);
    expect(response.body.account).toMatchObject({ signedInWith: "apple" });
    expect(response.body.plan).toMatchObject({ plan: "promo", active: true });
    const dump = JSON.stringify(response.body);
    expect(dump).not.toContain("SECRET SUBTITLE LINE");
    expect(dump).not.toContain(token);
  });

  it("у нового телефона — пустые списки, а не ошибка", async () => {
    const w = await appleWorld();
    const response = await w.call("GET", "/v1/me/export", undefined, await w.device());
    expect(response.status).toBe(200);
    expect(response.body.episodes).toEqual([]);
    expect(response.body.usage).toEqual([]);
    expect(response.body.account).toBeNull();
  });

  it("без токена не отдаёт ничего", async () => {
    const w = await appleWorld();
    expect((await w.call("GET", "/v1/me/export")).status).toBe(401);
  });
});

describe("чистка аккаунтов", () => {
  it("удаляет аккаунт без телефонов через год", async () => {
    const w = await appleWorld();
    const a = await w.device();
    await w.signIn(a);
    await w.call("POST", "/v1/account/logout", {}, a);
    await purge(w.db, w.now() + (RETENTION.inactiveDeviceDays - 1) * DAY);
    expect(w.count("accounts")).toBe(1);
    await purge(w.db, w.now() + (RETENTION.inactiveDeviceDays + 2) * DAY);
    expect(w.count("accounts")).toBe(0);
  });

  it("не удаляет промокод, принадлежащий аккаунту без телефонов", async () => {
    const w = await appleWorld();
    const a = await w.device();
    await w.signIn(a);
    await w.addPromo(CODE);
    await w.call("POST", "/v1/promo/redeem", { code: CODE }, a);
    await w.call("POST", "/v1/account/logout", {}, a);
    await purge(w.db, w.now() + 2 * DAY);
    expect(w.count("entitlements")).toBe(1);
  });
});

describe("шифрование refresh token", () => {
  const random = (count: number) => crypto.getRandomValues(new Uint8Array(count));

  it("расшифровывается тем же секретом", async () => {
    const sealed = await seal("pepper", "purpose", "token-value", random);
    expect(await open("pepper", "purpose", sealed)).toBe("token-value");
  });

  it("не расшифровывается другим секретом или назначением", async () => {
    const sealed = await seal("pepper", "purpose", "token-value", random);
    await expect(open("other", "purpose", sealed)).rejects.toThrow();
    await expect(open("pepper", "other", sealed)).rejects.toThrow();
  });

  it("замечает подмену шифротекста", async () => {
    const sealed = await seal("pepper", "purpose", "token-value", random);
    const tampered = sealed.slice(0, -2) + (sealed.endsWith("A") ? "BB" : "AA");
    await expect(open("pepper", "purpose", tampered)).rejects.toThrow();
  });
});

describe("какой доступ лучше", () => {
  const now = 1_000;
  const e = (kind: Entitlement["kind"], periodEnd: number, id = kind + periodEnd): Entitlement => ({
    id, kind, units_per_period: 1, used: 0, reserved: 0, period_start: 0, period_end: periodEnd,
    original_transaction_id: null, product_id: null,
  });

  it("действующий лучше истёкшего", () => {
    expect(better(e("subscription", 500), e("promo", 2_000), now)?.kind).toBe("promo");
  });
  it("подписка лучше промокода", () => {
    expect(better(e("promo", 9_000), e("subscription", 2_000), now)?.kind).toBe("subscription");
  });
  it("из двух одинаковых — с дальним сроком", () => {
    expect(better(e("promo", 2_000), e("promo", 3_000), now)?.period_end).toBe(3_000);
  });
  it("что угодно лучше, чем ничего", () => {
    expect(better(null, e("promo", 10), now)?.kind).toBe("promo");
    expect(better(null, null, now)).toBeNull();
  });
});
