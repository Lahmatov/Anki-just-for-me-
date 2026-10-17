import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { handle } from "../src/app";
import { CODE, makeWorld } from "./helpers";

/**
 * Контракт API между приложением и сервером (P-71).
 *
 * Запросы (schema/api/requests) — ровно то, что шлёт приложение; ядро
 * проверяет, что кодирует их так же (ContractTests), а здесь — что сервер их
 * принимает. Ответы (schema/api/responses) пишет этот тест; ядро проверяет,
 * что умеет их прочесть. Сервер может добавлять поля — убрать или сменить
 * тип поля нельзя: старые приложения перестали бы понимать ответ.
 * Обновить ответы: UPDATE_API=1 npx vitest run test/contract.test.ts.
 */
const ROOT = new URL("../../schema/api/", import.meta.url);

interface Fixture { route: string; body: Record<string, unknown> }

function requestFixture(name: string): Fixture {
  return JSON.parse(readFileSync(new URL(`requests/${name}.json`, ROOT), "utf8")) as Fixture;
}

/** Форма значения: тип у каждого ключа; массив — по первому элементу. */
type Shape = string | { [key: string]: Shape } | Shape[];
function shape(value: unknown): Shape {
  if (value === null) return "null";
  if (Array.isArray(value)) return value.length ? [shape(value[0])] : [];
  if (typeof value === "object") {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>).map(([k, v]) => [k, shape(v)]));
  }
  return typeof value;
}

/** Всё, что было в старом ответе, есть и в новом, того же типа. */
function missing(old: Shape, now: Shape, path = ""): string[] {
  if (old === "null") return [];
  if (typeof old === "string") return old === now ? [] : [`${path}: ${old} → ${JSON.stringify(now)}`];
  if (Array.isArray(old)) {
    if (!Array.isArray(now)) return [`${path}: массив → ${JSON.stringify(now)}`];
    return old.length && now.length ? missing(old[0]!, now[0]!, path + "[]") : [];
  }
  if (typeof now !== "object" || Array.isArray(now)) return [`${path}: объект → ${JSON.stringify(now)}`];
  return Object.entries(old).flatMap(([key, value]) =>
    key in now ? missing(value, now[key]!, `${path}.${key}`) : [`${path}.${key}: пропало`]);
}

async function send(w: ReturnType<typeof makeWorld>, route: string, body: unknown, token?: string) {
  const [method, path] = route.split(" ") as [string, string];
  const headers: Record<string, string> = { "cf-connecting-ip": "1.2.3.4" };
  if (token) headers.authorization = `Bearer ${token}`;
  if (body !== undefined) headers["content-type"] = "application/json";
  const response = await handle(new Request("https://api.test" + path, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body),
  }), w.env, w.deps);
  return { status: response.status, body: await response.json() as Record<string, unknown> };
}

describe("контракт API", async () => {
  const w = makeWorld();
  await w.addPromo(CODE, 30, 100_000);
  const token = await w.device();
  const responses: Record<string, Record<string, unknown>> = {};

  responses["redeem"] = (await send(w, "POST /v1/promo/redeem", { code: CODE }, token)).body;
  responses["me"] = (await send(w, "GET /v1/me", undefined, token)).body;
  responses["health"] = (await send(w, "GET /v1/health", undefined)).body;

  const accepted: Record<string, number> = {};
  // Порядок важен: разговор о серии открывается после слов к ней.
  for (const name of ["deck", "lesson", "discuss", "lesson-chat", "support"]) {
    if (name === "discuss" || name === "lesson-chat") {
      w.claude.reply = () => ({
        text: JSON.stringify({ reply: "Olá!", tip: { said: "", better: "", why: "" }, finished: false,
                               onTopic: true }),
        inputTokens: 100, outputTokens: 20,
      });
    }
    const fixture = requestFixture(name);
    const result = await send(w, fixture.route, fixture.body, token);
    accepted[name] = result.status;
    responses[name] = result.body;
  }

  const upload = await handle(new Request(
    "https://api.test/v1/backups?device=iPhone&notes=2&mature=0&language=pt-PT", {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/octet-stream" },
      body: new Uint8Array([1, 2, 3, 4]),
    }), w.env, w.deps);
  responses["backup-upload"] = await upload.json() as Record<string, unknown>;
  responses["backups"] = (await send(w, "GET /v1/backups?language=pt-PT", undefined, token)).body;
  responses["support-list"] = (await send(w, "GET /v1/support", undefined, token)).body;

  if (process.env.UPDATE_API) {
    for (const [name, body] of Object.entries(responses)) {
      writeFileSync(new URL(`responses/${name}.json`, ROOT), JSON.stringify(body, null, 2) + "\n");
    }
  }

  it("все запросы приложения сервер принимает", () => {
    const files = readdirSync(new URL("requests/", ROOT)).map((file) => file.replace(".json", ""));
    expect(files.sort()).toEqual(Object.keys(accepted).sort());
    for (const [name, status] of Object.entries(accepted)) expect([200, 201], name).toContain(status);
  });

  for (const name of readdirSync(new URL("responses/", ROOT)).map((file) => file.replace(".json", ""))) {
    it(`ответ «${name}» не потерял полей`, () => {
      const stored = JSON.parse(readFileSync(new URL(`responses/${name}.json`, ROOT), "utf8"));
      expect(responses[name], `ответ ${name} больше не снимается`).toBeDefined();
      expect(missing(shape(stored), shape(responses[name]))).toEqual([]);
    });
  }

  it("проверка формы ловит пропажу и смену типа", () => {
    expect(missing(shape({ a: 1, b: { c: "x" } }), shape({ a: 2, b: { c: "y", d: 1 } }))).toEqual([]);
    expect(missing(shape({ a: 1 }), shape({}))).toEqual([".a: пропало"]);
    expect(missing(shape({ a: 1 }), shape({ a: "1" }))).toHaveLength(1);
    expect(missing(shape({ list: [{ id: "x" }] }), shape({ list: [{}] }))).toEqual([".list[].id: пропало"]);
  });
});
