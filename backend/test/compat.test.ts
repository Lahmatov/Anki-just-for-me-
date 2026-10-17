import { describe, expect, it } from "vitest";
import { handle } from "../src/app";
import { clientBuild, featureOf } from "../src/compat";
import { CODE, DECK_REQUEST, makeWorld } from "./helpers";

/** Совместимость с приложениями разных версий и аварийный выключатель (P-71). */

function withClient(path: string, init: RequestInit, build?: string): Request {
  const headers = new Headers(init.headers);
  if (build) headers.set("x-recap-client", build);
  return new Request("https://api.test" + path, { ...init, headers });
}

describe("здоровье сервера", () => {
  it("отвечает без авторизации и без данных людей", async () => {
    const w = makeWorld();
    const response = await w.call("GET", "/v1/health");
    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ ok: true, api: 1, version: "dev", backups: "d1" });
    expect(JSON.stringify(response.body)).not.toMatch(/token|device/i);
  });

  it("показывает, что развёрнуто и куда идут бэкапы", async () => {
    const w = makeWorld({ r2: true });
    w.env.BUILD_VERSION = "abc1234";
    w.env.MIN_CLIENT_BUILD = "12";
    const response = await w.call("GET", "/v1/health");
    expect(response.body).toMatchObject({ version: "abc1234", minClientBuild: 12, backups: "r2" });
  });

  it("каждый ответ несёт версию API", async () => {
    const w = makeWorld();
    const response = await handle(new Request("https://api.test/v1/health"), w.env, w.deps);
    expect(response.headers.get("x-recap-api")).toBe("1");
  });
});

describe("слишком старое приложение", () => {
  it("номер сборки читается из заголовка, мусор — не номер", () => {
    const request = (value: string) => new Request("https://x", { headers: { "x-recap-client": value } });
    expect(clientBuild(request("ios/0.4 (17)"))).toBe(17);
    expect(clientBuild(request("ios/0.4"))).toBeNull();
    expect(clientBuild(request("ios/0.4 (abc)"))).toBeNull();
    expect(clientBuild(new Request("https://x"))).toBeNull();
  });

  it("получает 426 с просьбой обновиться", async () => {
    const w = makeWorld();
    w.env.MIN_CLIENT_BUILD = "20";
    const token = await w.device();
    const response = await handle(withClient("/v1/deck", {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify(DECK_REQUEST),
    }, "ios/0.3 (19)"), w.env, w.deps);
    expect(response.status).toBe(426);
    expect(((await response.json()) as { error: string }).error).toBe("upgrade_required");
  });

  /** Права на свои данные не зависят от версии приложения. */
  it("всё равно может выгрузить и удалить свои данные", async () => {
    const w = makeWorld();
    w.env.MIN_CLIENT_BUILD = "20";
    const token = await w.device();
    const auth = { authorization: `Bearer ${token}` };
    for (const [method, path] of [["GET", "/v1/me/export"], ["GET", "/v1/backups"],
                                  ["DELETE", "/v1/backups"], ["DELETE", "/v1/me"]] as const) {
      const response = await handle(withClient(path, { method, headers: auth }, "ios/0.1 (1)"), w.env, w.deps);
      expect(response.status, `${method} ${path}`).not.toBe(426);
    }
  });

  it("свежая сборка и запрос без заголовка проходят", async () => {
    const w = makeWorld();
    w.env.MIN_CLIENT_BUILD = "20";
    const fresh = await handle(withClient("/v1/devices", { method: "POST" }, "ios/1.0 (20)"), w.env, w.deps);
    expect(fresh.status).toBe(201);
    const old = await handle(withClient("/v1/devices", { method: "POST" }), w.env, w.deps);
    expect(old.status).toBe(201);
  });

  it("без порога проверки нет вовсе", async () => {
    const w = makeWorld();
    const response = await handle(withClient("/v1/devices", { method: "POST" }, "ios/0.1 (1)"), w.env, w.deps);
    expect(response.status).toBe(201);
  });
});

describe("аварийный выключатель", () => {
  it("выключенная функция отвечает 503, остальные работают", async () => {
    const w = makeWorld();
    await w.addPromo(CODE, 30, 100_000);
    const token = await w.device();
    await w.call("POST", "/v1/promo/redeem", { code: CODE }, token);
    w.env.DISABLED_FEATURES = "lesson, help";
    const lesson = await w.call("POST", "/v1/lesson", {
      lesson: "comer", language: "ru", target: "pt-PT", wordCount: 10, knownTerms: [],
    }, token);
    expect(lesson.status).toBe(503);
    expect(lesson.body.error).toBe("feature_disabled");
    expect(w.claude.calls).toHaveLength(0);
    expect((await w.call("POST", "/v1/deck", DECK_REQUEST, token)).status).toBe(200);
  });

  it("«all» выключает все функции ИИ и загрузку копий, но не данные и здоровье", async () => {
    const w = makeWorld();
    const token = await w.device();
    w.env.DISABLED_FEATURES = "all";
    expect((await w.call("POST", "/v1/deck", DECK_REQUEST, token)).status).toBe(503);
    expect((await w.call("GET", "/v1/health")).status).toBe(200);
    expect((await w.call("GET", "/v1/me", undefined, token)).status).toBe(200);
    expect((await w.call("GET", "/v1/me/export", undefined, token)).status).toBe(200);
  });

  it("у каждого маршрута ИИ есть имя для выключателя", () => {
    for (const route of ["POST /v1/deck", "POST /v1/lesson", "POST /v1/discuss", "POST /v1/lesson/chat",
                         "POST /v1/help"]) {
      expect(featureOf(route), route).not.toBeNull();
    }
    expect(featureOf("GET /v1/me")).toBeNull();
  });
});
