import { describe, expect, it } from "vitest";
import { handle } from "../src/app";
import { CODE, makeWorld } from "./helpers";

/**
 * Сквозной путь одного человека через сервер — как его проходит приложение:
 * регистрация телефона → промокод → карточки из урока → разговор об уроке →
 * облачная копия португальской базы → выгрузка данных → удаление.
 * Отдельные шаги проверены в своих файлах; здесь — что они работают вместе
 * и состояние одного шага не ломает следующий.
 */
describe("сквозной путь: урок португальского от промокода до удаления", () => {
  it("проходится целиком", async () => {
    const w = makeWorld();
    await w.addPromo(CODE, 30, 100_000);

    // 1. Телефон регистрируется и активирует промокод.
    const token = await w.device();
    const redeemed = await w.call("POST", "/v1/promo/redeem", { code: CODE }, token);
    expect(redeemed.status).toBe(200);
    const me = await w.call("GET", "/v1/me", undefined, token);
    expect(me.status).toBe(200);

    // 2. Карточки из урока; повтор после обрыва — без второго вызова модели.
    w.claude.reply = () => ({
      text: JSON.stringify({ name: "Pretérito perfeito", notes: [
        { term: "comer", translation: "есть", ipa: "", partOfSpeech: "verb", example: "Ontem comi.",
          exampleTranslation: "Вчера я ел.", cloze: "Ontem ___.", note: "" },
        { term: "estar a + infinitivo", translation: "действие сейчас", ipa: "", partOfSpeech: "other",
          example: "Estou a comer.", exampleTranslation: "Я ем.", cloze: "Estou a ___.", note: "" },
      ] }),
      inputTokens: 900, outputTokens: 400,
    });
    const lessonBody = { lesson: "Aula 5: comer, estar a + infinitivo", language: "ru", target: "pt-PT",
                         level: "A2", wordCount: 20, knownTerms: [], requestId: "journey-lesson-1" };
    const lesson = await w.call("POST", "/v1/lesson", lessonBody, token);
    expect(lesson.status).toBe(200);
    expect(lesson.body.deck.deck).toEqual({ name: "Pretérito perfeito", folder: "Уроки" });
    const again = await w.call("POST", "/v1/lesson", lessonBody, token);
    expect(again.body.deck).toEqual(lesson.body.deck);
    expect(w.claude.calls).toHaveLength(1);

    // 3. Разговор об уроке: две реплики Мончика, вторая — на подписанной истории.
    const terms = lesson.body.deck.notes.map((note: { term: string }) => note.term);
    w.claude.reply = () => ({
      text: JSON.stringify({ reply: "Olá! O que comeste ontem?", tip: { said: "", better: "", why: "" },
                             finished: false, onTopic: true }),
      inputTokens: 300, outputTokens: 40,
    });
    const chat = { title: lesson.body.deck.deck.name, terms, language: "ru", target: "pt-PT" };
    const first = await w.call("POST", "/v1/lesson/chat", { ...chat, turns: [] }, token);
    expect(first.status).toBe(200);
    w.claude.reply = () => ({
      text: JSON.stringify({ reply: "Muito bem!", tip: { said: "comi bacalhau ontem",
                             better: "ontem comi bacalhau", why: "порядок слов" }, finished: false, onTopic: true }),
      inputTokens: 300, outputTokens: 40,
    });
    const second = await w.call("POST", "/v1/lesson/chat", { ...chat, turns: [
      { speaker: "monchik", text: first.body.reply, sig: first.body.turnSig },
      { speaker: "learner", text: "comi bacalhau ontem" },
    ] }, token);
    expect(second.status).toBe(200);
    expect(second.body.tip.better).toBe("ontem comi bacalhau");

    // 4. Облачная копия португальской базы — своя, английская полка пуста.
    const snapshot = new Uint8Array(4_096).map((_, index) => index & 0xff);
    const upload = await handle(new Request(
      "https://api.test/v1/backups?device=iPhone&notes=2&mature=0&language=pt-PT", {
        method: "POST",
        headers: { authorization: `Bearer ${token}`, "content-type": "application/octet-stream" },
        body: snapshot,
      }), w.env, w.deps);
    expect(upload.status).toBe(201);
    const portuguese = await w.call("GET", "/v1/backups?language=pt-PT", undefined, token);
    expect(portuguese.body.backups).toHaveLength(1);
    const english = await w.call("GET", "/v1/backups", undefined, token);
    expect(english.body.backups).toHaveLength(0);

    // 5. Выгрузка данных видит всё, что накопилось.
    const exported = await w.call("GET", "/v1/me/export", undefined, token);
    expect(exported.status).toBe(200);
    expect(JSON.stringify(exported.body)).toContain("pt-PT");

    // 6. Удаление: после него токен не работает, копий нет.
    const forgotten = await w.call("DELETE", "/v1/me", undefined, token);
    expect(forgotten.status).toBe(200);
    expect((await w.call("GET", "/v1/me", undefined, token)).status).toBe(401);
    expect(w.db.raw.prepare("SELECT COUNT(*) AS n FROM backups").get()).toEqual({ n: 0 });
  });
});
