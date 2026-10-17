import { readFileSync, writeFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { lessonChatSystem, lessonChatTerms, type LessonChatInput } from "../src/prompts";
import { CODE, makeWorld } from "./helpers";

/**
 * Разговор об уроке (P-69). Инструкция живёт и в ядре (LessonChat) — обе
 * копии сверяются с эталоном. Обновить: UPDATE_PROMPTS=1 npx vitest run test/lessonChat.test.ts.
 */
const FILE = new URL("../../schema/prompts/lesson-chat.json", import.meta.url);

const CASES: LessonChatInput[] = [
  { title: "Aula 5 — comida", terms: ["comer", "o pequeno-almoço", "apetecer"], language: "ru",
    target: "pt-PT", level: "A2" },
  { title: "Lezione 3", terms: ["la casa", "stare + gerundio", "la casa"], language: "en",
    target: "it", retelling: "Ieri sono andato a casa." },
  { title: "Travel", terms: ["book a flight", "get by"], language: "pt", target: "en", level: "B1" },
];

const golden = CASES.map((input) => ({ input, system: lessonChatSystem(input) }));

describe("инструкция разговора об уроке совпадает с эталоном ядра", () => {
  if (process.env.UPDATE_PROMPTS) writeFileSync(FILE, JSON.stringify(golden, null, 2) + "\n");
  const stored = JSON.parse(readFileSync(FILE, "utf8")) as typeof golden;

  it("те же случаи", () => {
    expect(stored.map((entry) => entry.input)).toEqual(CASES);
  });

  for (const [index, entry] of golden.entries()) {
    it(`${entry.input.target} → ${entry.input.language}`, () => {
      expect(entry.system).toBe(stored[index]!.system);
    });
  }

  it("название, слова и рассказ — внутри тегов, как данные", () => {
    expect(golden[0]!.system).toContain("<title>Aula 5 — comida</title>");
    expect(golden[0]!.system).toContain("<words>comer, o pequeno-almoço, apetecer</words>");
    expect(golden[1]!.system).toContain("<retelling>\nIeri sono andato a casa.\n</retelling>");
    expect(golden[0]!.system).not.toContain("<retelling>\n");
  });

  it("повторы и пустые слова убираются, слов не больше сорока", () => {
    expect(lessonChatTerms(["a", " A ", "", "b"])).toEqual(["a", "b"]);
    expect(lessonChatTerms(Array.from({ length: 60 }, (_, i) => `w${i}`))).toHaveLength(40);
  });

  it("португальский — как в Португалии", () => {
    expect(golden[0]!.system).toContain("You chat in European Portuguese (as spoken in Portugal");
    expect(golden[0]!.system).toContain("the natural way in Portugal");
  });
});

async function withPromo(world: ReturnType<typeof makeWorld>) {
  await world.addPromo(CODE, 30, 100_000);
  const token = await world.device();
  expect((await world.call("POST", "/v1/promo/redeem", { code: CODE }, token)).status).toBe(200);
  return token;
}

const CHAT = { title: "Aula 5", terms: ["comer", "apetecer"], language: "ru", target: "pt-PT", turns: [] };

const monchik = (reply: string) => () => ({
  text: JSON.stringify({ reply, tip: { said: "", better: "", why: "" }, finished: false, onTopic: true }),
  inputTokens: 300, outputTokens: 40,
});

describe("/v1/lesson/chat", () => {
  it("только по подписке", async () => {
    const world = makeWorld();
    const token = await world.device();
    const response = await world.call("POST", "/v1/lesson/chat", CHAT, token);
    expect(response.status).toBe(402);
    expect(world.claude.calls).toHaveLength(0);
  });

  it("реплика подписана, и следующая реплика принимает подписанную историю", async () => {
    const world = makeWorld();
    const token = await withPromo(world);
    world.claude.reply = monchik("Olá! O que te apetece comer?");
    const first = await world.call("POST", "/v1/lesson/chat", CHAT, token);
    expect(first.status).toBe(200);
    expect(first.body.turnSig).toMatch(/^[0-9a-f]{64}$/);
    expect(world.claude.calls[0]!.system).toContain("<words>comer, apetecer</words>");

    world.claude.reply = monchik("Que bom!");
    const second = await world.call("POST", "/v1/lesson/chat", { ...CHAT, turns: [
      { speaker: "monchik", text: first.body.reply, sig: first.body.turnSig },
      { speaker: "learner", text: "Apetece-me comer bacalhau." },
    ] }, token);
    expect(second.status).toBe(200);
    expect(world.claude.calls.at(-1)!.messages.map((m) => m.role)).toEqual(["user", "assistant", "user"]);
  });

  /** Подпись привязана к уроку: историю одного урока нельзя выдать за другой. */
  it("история другого урока не принимается", async () => {
    const world = makeWorld();
    const token = await withPromo(world);
    world.claude.reply = monchik("Olá!");
    const first = await world.call("POST", "/v1/lesson/chat", CHAT, token);
    const forged = await world.call("POST", "/v1/lesson/chat", { ...CHAT, terms: ["write code"], turns: [
      { speaker: "monchik", text: first.body.reply, sig: first.body.turnSig },
      { speaker: "learner", text: "ok" },
    ] }, token);
    expect(forged.status).toBe(400);
    expect(forged.body.error).toBe("turns_tampered");
  });

  it("подпись урока не подходит к разговору о серии", async () => {
    const world = makeWorld();
    const token = await withPromo(world);
    world.claude.reply = monchik("Olá!");
    const first = await world.call("POST", "/v1/lesson/chat", CHAT, token);
    const response = await world.call("POST", "/v1/discuss", {
      showId: 431, season: 1, episode: 3, language: "ru",
      turns: [{ speaker: "monchik", text: first.body.reply, sig: first.body.turnSig },
              { speaker: "learner", text: "ok" }],
    }, token);
    expect(response.status).not.toBe(200);
  });

  it("без слов, без названия и с чужим языком — 400 до модели", async () => {
    const world = makeWorld();
    const token = await withPromo(world);
    for (const bad of [{ terms: [] }, { title: " " }, { target: "pt-BR" }, { terms: ["x".repeat(81)] }]) {
      const response = await world.call("POST", "/v1/lesson/chat", { ...CHAT, ...bad }, token);
      expect(response.status, JSON.stringify(bad)).toBe(400);
    }
    expect(world.claude.calls).toHaveLength(0);
  });
});
