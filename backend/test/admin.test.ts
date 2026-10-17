import { describe, expect, it } from "vitest";
import { handle } from "../src/app";
import { normalizeSupportCode } from "../src/admin";
import { makeWorld } from "./helpers";

/** Запросы людей не из приложения (P-76): выгрузка и удаление по коду поддержки. */

const ADMIN = "admin-secret-0123456789abcdef0123456789abcdef";
const TICKET = { category: "privacy", message: "Удалите, пожалуйста, мои данные." };

function adminWorld(options: { r2?: boolean } = {}) {
  const w = makeWorld(options);
  w.env.ADMIN_TOKEN = ADMIN;
  return w;
}

async function codeOf(w: ReturnType<typeof makeWorld>, token: string): Promise<string> {
  return (await w.call("GET", "/v1/me", undefined, token)).body.supportCode as string;
}

async function upload(w: ReturnType<typeof makeWorld>, token: string) {
  const response = await handle(new Request("https://api.test/v1/backups?device=iPhone&notes=10&mature=1", {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/octet-stream" },
    body: new Uint8Array([82, 67, 66, 49, 1, 2, 3, 4]),
  }), w.env, w.deps);
  expect(response.status).toBe(201);
}

describe("служебный вход", () => {
  it("без секрета маршрутов нет", async () => {
    const w = makeWorld();
    const response = await w.call("POST", "/v1/admin/erase", { supportCode: "ABCD-1234" }, ADMIN);
    expect(response.status).toBe(404);
  });

  it("с чужим секретом — отказ", async () => {
    const w = adminWorld();
    const response = await w.call("POST", "/v1/admin/erase", { supportCode: "ABCD-1234" },
                                  "wrong-secret-0123456789abcdef0123456789ab");
    expect(response.status).toBe(401);
  });

  it("без секрета в запросе — отказ", async () => {
    const w = adminWorld();
    expect((await w.call("POST", "/v1/admin/export", { supportCode: "ABCD-1234" })).status).toBe(401);
  });

  it("токен устройства служебный вход не открывает", async () => {
    const w = adminWorld();
    const token = await w.device();
    const code = await codeOf(w, token);
    expect((await w.call("POST", "/v1/admin/export", { supportCode: code }, token)).status).toBe(401);
  });

  it("попытки ограничены", async () => {
    const w = adminWorld();
    for (let i = 0; i < 30; i++) await w.call("POST", "/v1/admin/export", { supportCode: "x" }, "nope".repeat(10));
    expect((await w.call("POST", "/v1/admin/export", { supportCode: "x" }, ADMIN)).status).toBe(429);
  });
});

describe("код поддержки", () => {
  it("принимается с дефисом и без, в любом регистре", () => {
    expect(normalizeSupportCode("ABCD-12EF")).toBe("abcd12ef");
    expect(normalizeSupportCode(" abcd12ef ")).toBe("abcd12ef");
  });

  it("чужой формат — не код", () => {
    for (const value of ["", "ABCD-123", "ABCD-12345", "WXYZ-1234", 12345678, null]) {
      expect(normalizeSupportCode(value)).toBeNull();
    }
  });

  it("негодный код — 400, неизвестный — 404", async () => {
    const w = adminWorld();
    expect((await w.call("POST", "/v1/admin/erase", { supportCode: "nope" }, ADMIN)).status).toBe(400);
    expect((await w.call("POST", "/v1/admin/erase", { supportCode: "0000-0000" }, ADMIN)).status).toBe(404);
  });

  it("два устройства с одним кодом — отказ, а не удаление наугад", async () => {
    const w = adminWorld();
    for (const id of ["abcd1234aaaaaaaaaaaaaaaaaaaaaaaa", "abcd1234bbbbbbbbbbbbbbbbbbbbbbbb"]) {
      w.db.raw.prepare("INSERT INTO devices (id, token_hash, created_at, last_seen_at) VALUES (?, ?, 0, 0)")
        .run(id, "hash-" + id);
    }
    const response = await w.call("POST", "/v1/admin/erase", { supportCode: "ABCD-1234" }, ADMIN);
    expect(response.status).toBe(409);
    expect(w.db.raw.prepare("SELECT COUNT(*) AS n FROM devices").get()).toEqual({ n: 2 });
  });
});

describe("номер обращения вместо кода", () => {
  it("находит телефон, с которого пришло обращение", async () => {
    const w = adminWorld();
    const token = await w.device();
    await w.device();
    const ticket = (await w.call("POST", "/v1/support", TICKET, token)).body.ticket.id as string;
    const response = await w.call("POST", "/v1/admin/erase", { supportCode: ticket.toLowerCase() }, ADMIN);
    expect(response.status).toBe(200);
    expect((await w.call("GET", "/v1/me", undefined, token)).status).toBe(401);
    expect(w.db.raw.prepare("SELECT COUNT(*) AS n FROM devices").get()).toEqual({ n: 1 });
  });

  it("неизвестный номер — 404", async () => {
    const w = adminWorld();
    expect((await w.call("POST", "/v1/admin/erase", { supportCode: "R-2222AA" }, ADMIN)).status).toBe(404);
  });
});

describe("выгрузка по коду", () => {
  it("совпадает с выгрузкой из приложения", async () => {
    const w = adminWorld();
    const token = await w.device();
    await w.call("POST", "/v1/support", TICKET, token);
    const own = await w.call("GET", "/v1/me/export", undefined, token);
    const byCode = await w.call("POST", "/v1/admin/export", { supportCode: await codeOf(w, token) }, ADMIN);
    expect(byCode.status).toBe(200);
    expect(byCode.body).toEqual(own.body);
    expect(byCode.body.supportTickets).toHaveLength(1);
  });
});

describe("удаление по коду", () => {
  it("стирает устройство: его токен больше не действует", async () => {
    const w = adminWorld();
    const token = await w.device();
    const response = await w.call("POST", "/v1/admin/erase", { supportCode: await codeOf(w, token) }, ADMIN);
    expect(response.status).toBe(200);
    expect(response.body).toEqual({ deleted: true, account: false });
    expect((await w.call("GET", "/v1/me", undefined, token)).status).toBe(401);
  });

  it("стирает обращения и снимки, включая объекты в R2", async () => {
    const w = adminWorld({ r2: true });
    const token = await w.device();
    await w.call("POST", "/v1/support", TICKET, token);
    await upload(w, token);
    expect(w.r2!.objects.size).toBe(1);
    await w.call("POST", "/v1/admin/erase", { supportCode: await codeOf(w, token) }, ADMIN);
    for (const table of ["support_tickets", "backups", "devices"]) {
      expect(w.db.raw.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get()).toEqual({ n: 0 });
    }
    expect(w.r2!.objects.size).toBe(0);
  });

  it("другие телефоны не трогает", async () => {
    const w = adminWorld();
    const erased = await w.device();
    const kept = await w.device();
    await w.call("POST", "/v1/support", TICKET, kept);
    await w.call("POST", "/v1/admin/erase", { supportCode: await codeOf(w, erased) }, ADMIN);
    expect((await w.call("GET", "/v1/me", undefined, kept)).status).toBe(200);
    expect(w.db.raw.prepare("SELECT COUNT(*) AS n FROM support_tickets").get()).toEqual({ n: 1 });
  });

  it("повтор после удаления — 404, а не ошибка сервера", async () => {
    const w = adminWorld();
    const code = await codeOf(w, await w.device());
    await w.call("POST", "/v1/admin/erase", { supportCode: code }, ADMIN);
    expect((await w.call("POST", "/v1/admin/erase", { supportCode: code }, ADMIN)).status).toBe(404);
  });
});
