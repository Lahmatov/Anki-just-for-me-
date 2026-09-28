import { describe, expect, it } from "vitest";
// @ts-expect-error — скрипт на чистом JS, типов у него нет.
import * as lib from "../scripts/catalog-lib.mjs";
import { makeDB } from "./d1";

describe("сборщик каталога", () => {
  it("custom_id туда и обратно, мусор — null", () => {
    expect(lib.parseCustomId(lib.customId(431, 1, 3))).toEqual({ showId: 431, season: 1, episode: 3 });
    expect(lib.parseCustomId("x-1")).toBeNull();
  });

  it("чистит ответ модели: без переводов и повторов слова нет", () => {
    const notes = lib.cleanNotes(JSON.stringify({ notes: [
      { term: "freak out", ipa: "/x/", partOfSpeech: "phrasal verb",
        translation: { ru: "психануть", pt: "passar-se", en: "to panic" },
        example: "Don't freak out.", exampleTranslation: { ru: "Не психуй.", pt: "" },
        cloze: "Don't ___ ___.", note: { ru: "", pt: "", en: "" } },
      { term: "Freak out", translation: { ru: "a", pt: "b", en: "c" } },
      { term: "no pt", translation: { ru: "a", pt: "", en: "c" } },
    ] }));
    expect(notes).toEqual([{
      term: "freak out", ipa: "/x/", partOfSpeech: "phrasal verb", example: "Don't freak out.",
      cloze: "Don't ___ ___.", translation: { ru: "психануть", pt: "passar-se", en: "to panic" },
      exampleTranslation: { ru: "Не психуй." },
    }]);
    expect(lib.cleanNotes("oops")).toEqual([]);
  });

  it("SQL загружается в схему и отдаётся сервером", async () => {
    const sql = lib.seedSQL(
      [{ id: 431, name: "Grey's Anatomy", posterURL: null, year: 2005, rank: 1 }],
      [{ showId: 431, season: 1, episode: 1, title: "S01E01 · It's a start",
         notes: [{ term: "scrub in", translation: { ru: "мыться", pt: "lavar-se", en: "to wash" } }] }]);
    const db = makeDB();
    db.raw.exec(sql);
    const { catalogNotes, listShows } = await import("../src/catalog");
    expect((await listShows(db))[0]).toMatchObject({ name: "Grey's Anatomy", decks: 1 });
    expect((await catalogNotes(db, 431, 1, 1))?.[0]?.term).toBe("scrub in");
  });

  it("цена оценивается для известных моделей", () => {
    expect(lib.estimateCost("claude-haiku-4-5", 600)).toBeGreaterThan(0);
    expect(lib.estimateCost("unknown", 600)).toBeNull();
  });

  it("список — ровно 50 разных сериалов", async () => {
    const { readFileSync } = await import("node:fs");
    const { shows } = JSON.parse(readFileSync(new URL("../catalog/shows.json", import.meta.url), "utf8"));
    expect(shows).toHaveLength(50);
    expect(new Set(shows.map((show: { name: string }) => show.name)).size).toBe(50);
  });
});
