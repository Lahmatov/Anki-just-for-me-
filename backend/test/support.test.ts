import { describe, expect, it } from "vitest";
import { purge } from "../src/retention";
import { mimeMessage, ticketNumber, type SupportMail } from "../src/support";
import { makeWorld } from "./helpers";

/** Поддержка (P-72): обращение из приложения, ответ в приложении, письмо владельцу. */

const TICKET = {
  category: "bug", message: "Диктант не читает фразу вслух на iPad.",
  contact: "anna@example.com",
  diagnostics: { app: "0.4 (17)", ios: "26.1", language: "ru", studyLanguage: "pt-PT", device: "iPad" },
};

describe("обращение в поддержку", () => {
  it("создаётся без подписки и получает номер для человека", async () => {
    const w = makeWorld();
    const token = await w.device();
    const response = await w.call("POST", "/v1/support", TICKET, token);
    expect(response.status).toBe(201);
    expect(response.body.ticket.id).toMatch(/^R-[2-9A-HJKMNP-Z]{6}$/);
    expect(response.body.ticket).toMatchObject({ category: "bug", status: "open", reply: null });
  });

  it("ответ поддержки виден в приложении", async () => {
    const w = makeWorld();
    const token = await w.device();
    const { body } = await w.call("POST", "/v1/support", TICKET, token);
    w.db.raw.prepare("UPDATE support_tickets SET reply = ?, status = 'answered', updated_at = ? WHERE id = ?")
      .run("Починили в 0.5 — обнови приложение.", w.now() + 60, body.ticket.id);
    const list = await w.call("GET", "/v1/support", undefined, token);
    expect(list.body.tickets).toHaveLength(1);
    expect(list.body.tickets[0]).toMatchObject({ status: "answered", reply: "Починили в 0.5 — обнови приложение." });
  });

  it("чужие обращения не видны", async () => {
    const w = makeWorld();
    const mine = await w.device();
    const other = await w.device();
    await w.call("POST", "/v1/support", TICKET, mine);
    expect((await w.call("GET", "/v1/support", undefined, other)).body.tickets).toEqual([]);
  });

  it("обращения аккаунта видны со второго телефона", async () => {
    const w = makeWorld();
    const first = await w.device();
    const second = await w.device();
    const ids = (w.db.raw.prepare("SELECT id FROM devices ORDER BY rowid").all() as { id: string }[]).map((r) => r.id);
    w.db.raw.prepare("INSERT INTO accounts (id, apple_sub_hash, created_at, last_seen_at) VALUES ('acc', 'h', 0, ?)")
      .run(w.now());
    w.db.raw.prepare("UPDATE devices SET account_id = 'acc'").run();
    await w.call("POST", "/v1/support", TICKET, first);
    expect(ids).toHaveLength(2);
    expect((await w.call("GET", "/v1/support", undefined, second)).body.tickets).toHaveLength(1);
  });

  it("мусор отклоняется до записи", async () => {
    const w = makeWorld();
    for (const bad of [{ category: "spam" }, { message: "  " }, { message: "x".repeat(4_001) },
                       { contact: "not-an-email" }, { diagnostics: { nested: { a: 1 } } },
                       { diagnostics: ["list"] }, { diagnostics: { "bad key": "x" } }]) {
      // Свой телефон на каждую попытку: лимит в час считается и с отказами.
      const token = await w.device();
      const response = await w.call("POST", "/v1/support", { ...TICKET, ...bad }, token);
      expect(response.status, JSON.stringify(bad)).toBe(400);
    }
    expect(w.db.raw.prepare("SELECT COUNT(*) AS n FROM support_tickets").get()).toEqual({ n: 0 });
  });

  it("без почты и диагностики — тоже можно", async () => {
    const w = makeWorld();
    const token = await w.device();
    const response = await w.call("POST", "/v1/support", { category: "idea", message: "Добавьте испанский" }, token);
    expect(response.status).toBe(201);
  });

  it("не больше пяти обращений в час", async () => {
    const w = makeWorld();
    const token = await w.device();
    for (let index = 0; index < 5; index++) {
      expect((await w.call("POST", "/v1/support", TICKET, token)).status).toBe(201);
    }
    expect((await w.call("POST", "/v1/support", TICKET, token)).status).toBe(429);
  });

  it("выключатель останавливает приём обращений", async () => {
    const w = makeWorld();
    const token = await w.device();
    w.env.DISABLED_FEATURES = "support";
    expect((await w.call("POST", "/v1/support", TICKET, token)).status).toBe(503);
  });
});

describe("письмо владельцу", () => {
  it("уходит с номером, текстом и адресом для ответа", async () => {
    const w = makeWorld();
    const sent: SupportMail[] = [];
    w.env.SUPPORT_TO = "support@recap.example";
    w.deps.sendSupportMail = async (mail) => { sent.push(mail); };
    const pending: Promise<unknown>[] = [];
    w.deps.waitUntil = (promise) => { pending.push(promise); };
    const token = await w.device();
    const { body } = await w.call("POST", "/v1/support", TICKET, token);
    await Promise.all(pending);
    expect(sent).toHaveLength(1);
    expect(sent[0]!.to).toBe("support@recap.example");
    expect(sent[0]!.subject).toContain(body.ticket.id);
    expect(sent[0]!.text).toContain("Диктант не читает");
    expect(sent[0]!.replyTo).toBe("anna@example.com");
  });

  it("сбой почты не теряет обращение", async () => {
    const w = makeWorld();
    w.env.SUPPORT_TO = "support@recap.example";
    w.deps.sendSupportMail = async () => { throw new Error("mail down"); };
    const pending: Promise<unknown>[] = [];
    w.deps.waitUntil = (promise) => { pending.push(promise); };
    const token = await w.device();
    expect((await w.call("POST", "/v1/support", TICKET, token)).status).toBe(201);
    await Promise.all(pending);
    expect(w.db.raw.prepare("SELECT COUNT(*) AS n FROM support_tickets").get()).toEqual({ n: 1 });
  });

  it("MIME: тема и текст в UTF-8 base64 читаются обратно", () => {
    const raw = mimeMessage("bot@recap.example", { to: "me@recap.example", subject: "[Recap R-ABCDEF] bug",
                                                   text: "Привет, Мончик", replyTo: "a@b.co" },
                            "id-1", new Date(Date.UTC(2026, 9, 17)));
    expect(raw).toContain("Reply-To: a@b.co");
    expect(raw).toContain("Content-Type: text/plain; charset=UTF-8");
    const body = raw.split("\r\n\r\n")[1]!.replace(/\r\n/g, "");
    expect(new TextDecoder().decode(Uint8Array.from(atob(body), (c) => c.charCodeAt(0)))).toBe("Привет, Мончик");
    const subject = /Subject: =\?UTF-8\?B\?(.+)\?=/.exec(raw)![1]!;
    expect(atob(subject)).toBe("[Recap R-ABCDEF] bug");
  });

  it("номер обращения — без похожих букв", () => {
    expect(ticketNumber(new Uint8Array([0, 1, 2, 3, 4, 5]))).toBe("R-234567");
    expect(ticketNumber(new Uint8Array(6).fill(255))).not.toMatch(/[01IOL]/);
  });
});

describe("данные обращений и GDPR", () => {
  it("попадают в выгрузку", async () => {
    const w = makeWorld();
    const token = await w.device();
    await w.call("POST", "/v1/support", TICKET, token);
    const exported = await w.call("GET", "/v1/me/export", undefined, token);
    expect(exported.body.supportTickets).toHaveLength(1);
    expect(exported.body.supportTickets[0].message).toBe(TICKET.message);
    expect(exported.body.retentionDays.supportTicket).toBe(365);
  });

  it("удаляются с «Удалить все данные»", async () => {
    const w = makeWorld();
    const token = await w.device();
    await w.call("POST", "/v1/support", TICKET, token);
    await w.call("DELETE", "/v1/me", undefined, token);
    expect(w.db.raw.prepare("SELECT COUNT(*) AS n FROM support_tickets").get()).toEqual({ n: 0 });
  });

  it("чистятся через год и вместе с забытым телефоном", async () => {
    const w = makeWorld();
    const token = await w.device();
    await w.call("POST", "/v1/support", TICKET, token);
    w.advance(366 * 86_400);
    const report = await purge(w.db, w.now());
    expect(report.supportTickets).toBe(1);
    expect(w.db.raw.prepare("SELECT COUNT(*) AS n FROM support_tickets").get()).toEqual({ n: 0 });
  });

  it("свежее обращение живого телефона чистка не трогает", async () => {
    const w = makeWorld();
    const token = await w.device();
    await w.call("POST", "/v1/support", TICKET, token);
    await purge(w.db, w.now());
    expect(w.db.raw.prepare("SELECT COUNT(*) AS n FROM support_tickets").get()).toEqual({ n: 1 });
  });
});
