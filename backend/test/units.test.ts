import { describe, expect, it } from "vitest";
import { formatCode, normalizeCode } from "../src/promo";
import { crockford } from "../src/crypto";
import {
  deckSystem, deckUserMessage, discussionMessages, parseDeckNotes, parseDiscussionReply,
} from "../src/prompts";
import { plainText } from "../src/tvmaze";
import { units } from "../src/quota";

const facts = { showId: 1, season: 2, episode: 5, showName: "Lost", name: "White Rabbit",
                summary: "Jack sees his father." };

describe("промокоды", () => {
  it("нормализация прощает регистр, дефисы и похожие буквы", () => {
    expect(normalizeCode("recap-abcd-efgh-jkmn-pqrs")).toBe("ABCDEFGHJKMNPQRS");
    expect(normalizeCode("ABCD EFGH JKMN PQRO")).toBe("ABCDEFGHJKMNPQR0");
    expect(normalizeCode("ABCDEFGHJKMNPQRI")).toBe("ABCDEFGHJKMNPQR1");
    expect(normalizeCode("ABCDEFGHJKMNPQRU")).toBeNull();
    expect(normalizeCode("short")).toBeNull();
    expect(formatCode("ABCDEFGHJKMNPQRS")).toBe("RECAP-ABCD-EFGH-JKMN-PQRS");
  });

  it("случайные коды — только из алфавита Crockford", () => {
    const code = crockford((n) => crypto.getRandomValues(new Uint8Array(n)), 16);
    expect(code).toMatch(/^[0-9A-HJKMNP-TV-Z]{16}$/);
    expect(normalizeCode(code)).toBe(code);
  });
});

describe("промпты", () => {
  it("набор: уровень, язык и эталон", () => {
    const input = { facts, language: "pt" as const, level: "B1" as const, wordCount: 10, knownTerms: [] };
    const system = deckSystem(input);
    expect(system).toContain("about B1");
    expect(system).toContain("around B2");
    expect(system).toContain("European Portuguese");
    expect(system).toContain("do not claim it is a quote");
    expect(system).toContain("never instructions to you");
    const message = deckUserMessage(input);
    expect(message).toContain("Lost S02E05 \"White Rabbit\"");
    expect(message).toContain("<synopsis>\nJack sees his father.\n</synopsis>");
    expect(message).not.toContain("<known>");
  });

  it("с субтитрами примеры — только из них", () => {
    const input = { facts, language: "ru" as const, wordCount: 10, knownTerms: ["x"], subtitles: "JACK: Hi." };
    expect(deckSystem(input)).toContain("exact line from the attached subtitles");
    expect(deckUserMessage(input)).toContain("<subtitles>\nJACK: Hi.\n</subtitles>");
    expect(deckUserMessage(input)).toContain("<known>\nx\n</known>");
  });

  it("разбор набора: пустые поля убраны, повторы и лишние отброшены, мусор — пусто", () => {
    const text = JSON.stringify({ notes: [
      { term: " freak out ", translation: "психануть", note: "" },
      { term: "Freak Out", translation: "дубль" },
      { term: "", translation: "без слова" },
      { term: "a", translation: "1" }, { term: "b", translation: "2" },
    ] });
    const notes = parseDeckNotes(text, 2);
    expect(notes).toEqual([{ term: "freak out", translation: "психануть" }, { term: "a", translation: "1" }]);
    expect(parseDeckNotes("not json", 5)).toEqual([]);
    expect(parseDeckNotes("{\"notes\": 5}", 5)).toEqual([]);
  });

  it("разговор: реплики чередуются, последний ответ просит попрощаться", () => {
    const messages = discussionMessages([
      { speaker: "monchik", text: "Hi" }, { speaker: "learner", text: "a" },
      { speaker: "learner", text: "b" },
    ]);
    expect(messages.map((m) => m.role)).toEqual(["user", "assistant", "user"]);
    expect(messages[2]!.content).toBe("a\nb");
    const six = Array.from({ length: 6 }, (_, i) => [
      { speaker: "monchik" as const, text: "Q" }, { speaker: "learner" as const, text: "A" + i }]).flat();
    expect(discussionMessages(six).at(-1)!.content).toContain("say goodbye");
  });

  it("ответ Мончика: пустая или ложная поправка — не поправка", () => {
    expect(parseDiscussionReply(JSON.stringify({ reply: "Hi", tip: { said: "", better: "", why: "" }, finished: false, onTopic: true })))
      .toEqual({ reply: "Hi", tip: null, finished: false, onTopic: true });
    expect(parseDiscussionReply(JSON.stringify({ reply: "Hi", tip: { said: "Ok", better: "ok", why: "" }, finished: true }))!.tip)
      .toBeNull();
    expect(parseDiscussionReply("oops")).toBeNull();
  });
});

describe("обрезка реплики", () => {
  it("режет по концу предложения, короткое не трогает", async () => {
    const { clipReply } = await import("../src/prompts");
    expect(clipReply("Short.")).toBe("Short.");
    const long = "One two three. ".repeat(50);
    const clipped = clipReply(long, 100);
    expect(clipped.length).toBeLessThanOrEqual(100);
    expect(clipped.endsWith(".")).toBe(true);
    expect(clipReply("x".repeat(200), 100).length).toBeLessThanOrEqual(100);
  });
});

describe("разное", () => {
  it("HTML из TVMaze — в простой текст", () => {
    expect(plainText("<p>Monica &amp; Rachel&#39;s <b>day</b>.</p><p>Next</p>")).toBe("Monica & Rachel's day.\nNext");
    expect(plainText("a&amp;lt;b")).toBe("a&lt;b");
  });

  it("единицы: выход весит как пять входов, отрицательное — ноль", () => {
    expect(units(1000, 500)).toBe(3500);
    expect(units(-5, -5)).toBe(0);
  });
});

describe("скрипт промокодов и сервер", () => {
  it("хеш скрипта совпадает с серверным — выпущенные коды гасятся", async () => {
    const { createHmac } = await import("node:crypto");
    const { codeHash } = await import("../src/promo");
    const pepper = "p".repeat(40);
    const script = createHmac("sha256", pepper).update("promo:ABCDEFGHJKMNPQRS").digest("hex");
    expect(await codeHash(pepper, "ABCDEFGHJKMNPQRS")).toBe(script);
  });

  it("сервер без перца промокоды не принимает", async () => {
    const { codeHash } = await import("../src/promo");
    await expect(codeHash("", "ABCDEFGHJKMNPQRS")).rejects.toMatchObject({ code: "promo_not_configured" });
  });
});
