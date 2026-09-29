import { describe, expect, it } from "vitest";
// @ts-expect-error — скрипт на чистом JS, типов у него нет.
import * as lib from "../scripts/catalog-lib.mjs";
import { makeDB } from "./d1";
import { localizeNotes } from "../src/catalog";

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

describe("каталог на языке человека", () => {
  const notes = [
    { term: "pitch", translation: { ru: "подача идеи", pt: "apresentação", en: "to try to sell an idea" } },
    { term: "startup", translation: { ru: "", pt: "startup", en: "a new small company" } },
  ];

  it("слово без перевода на нужный язык пропускается, а не подменяется английским", () => {
    const ru = localizeNotes(notes as never, "ru", []);
    expect(ru.map((note) => note.term)).toEqual(["pitch"]);
    expect(ru[0]!.translation).toBe("подача идеи");
  });

  it("английский интерфейс получает английские толкования", () => {
    expect(localizeNotes(notes as never, "en", []).map((note) => note.translation))
      .toEqual(["to try to sell an idea", "a new small company"]);
  });

  it("уже известные слова не повторяются", () => {
    expect(localizeNotes(notes as never, "pt", ["PITCH"]).map((note) => note.term)).toEqual(["startup"]);
  });
});

describe("слова, собранные заранее", () => {
  const good = (term: string) =>
    `${term} | /x/ | phrase | рус | port | english | Say [${term}] now. | Скажи. | Diz.`;
  const file = (body: string) => `# show: Friends\n# year: 1994\n## 1 · Pilot\n${body}\n`;
  const five = ["a", "b", "c", "d", "e"].map(good).join("\n");

  it("строка превращается в слово с пропуском и переводами примера", () => {
    const { episodes, errors } = lib.parseWordsFile(file(five));
    expect(errors).toEqual([]);
    expect(episodes[0]).toMatchObject({ season: 1, episode: 1, title: "Pilot" });
    expect(episodes[0].notes[0]).toEqual({
      term: "a", ipa: "/x/", partOfSpeech: "phrase",
      translation: { ru: "рус", pt: "port", en: "english" },
      example: "Say a now.", cloze: "Say ___ now.",
      exampleTranslation: { ru: "Скажи.", pt: "Diz." },
    });
  });

  it("заметки — только непустые, по трём последним колонкам", () => {
    const line = "x | /x/ | idiom | р | п | e | A [x]. | Р. | П. | ловушка |  | trap";
    const { episodes } = lib.parseWordsFile(file(five + "\n" + line));
    expect(episodes[0].notes[5].note).toEqual({ ru: "ловушка", en: "trap" });
  });

  it("неверное число колонок — ошибка с номером строки", () => {
    const { errors } = lib.parseWordsFile(file(five + "\nx | y | z"));
    expect(errors.join()).toMatch(/words\.txt:9: 3 колонок/);
  });

  it("пример без пометки или с двумя пометками — ошибка", () => {
    const none = "x | /x/ | noun | р | п | e | No mark. | Р. | П.";
    const two = "y | /y/ | noun | р | п | e | [One] and [two]. | Р. | П.";
    const { errors } = lib.parseWordsFile(file(five + "\n" + none + "\n" + two));
    expect(errors.filter((error: string) => /ровно одна/.test(error))).toHaveLength(2);
  });

  it("неизвестная часть речи, пустой перевод и транскрипция без черт — ошибки", () => {
    const lines = [
      "x | /x/ | thing | р | п | e | A [x]. | Р. | П.",
      "y | /y/ | noun |  | п | e | A [y]. | Р. | П.",
      "z | zz | noun | р | п | e | A [z]. | Р. | П.",
    ];
    const { errors } = lib.parseWordsFile(file(five + "\n" + lines.join("\n")));
    expect(errors).toHaveLength(3);
  });

  it("повтор слова в серии и повтор серии — ошибки", () => {
    const text = file(five + "\n" + good("A")) + "## 1 · Again\n" + five;
    const { errors } = lib.parseWordsFile(text);
    expect(errors.join()).toMatch(/«A» уже есть/);
    expect(errors.join()).toMatch(/серия 1 уже была/);
  });

  it("серия меньше чем из пяти слов, слово до серии и нет названия сериала — ошибки", () => {
    expect(lib.parseWordsFile(`## 1\n${good("a")}`).errors).toHaveLength(2);
    expect(lib.parseWordsFile(`${good("a")}`).errors.join()).toMatch(/до первой серии/);
  });

  it("комментарии, пустые строки и BOM не мешают", () => {
    const { errors } = lib.parseWordsFile("﻿// заметка\n\n" + file(five));
    expect(errors).toEqual([]);
  });

  it("пустой и мусорный файл не роняют разбор", () => {
    expect(lib.parseWordsFile("").errors.join()).toMatch(/нет строки «# show/);
    expect(lib.parseWordsFile(undefined).episodes).toEqual([]);
  });

  it("каталог берёт ранг из списка сериалов, чужой сериал — ошибка", () => {
    const parsed = [lib.parseWordsFile(file(five)), lib.parseWordsFile(file(five).replace("Friends", "Nope"))];
    const bundle = lib.buildBundle(parsed, [{ rank: 1, name: "Friends", year: 1994, accent: "US" }]);
    expect(bundle.errors).toEqual(["«Nope» нет в catalog/shows.json"]);
    expect(bundle.index.shows).toEqual([{ resource: "catalog-show-01", name: "Friends", year: 1994,
      accent: "US", rank: 1, episodes: 1, words: 5 }]);
    expect(bundle.files["catalog-show-01"].episodes[0].notes).toHaveLength(5);
  });

  it("наборы для базы: номер и название серии — из TVMaze, сериал без номера пропущен", () => {
    const bundle = lib.buildBundle([lib.parseWordsFile(file(five))],
                                   [{ rank: 1, name: "Friends", year: 1994 }, { rank: 2, name: "Other" }]);
    const planned = [{ id: 431, name: "Friends", year: 1994, posterURL: "https://p",
                       episodes: [{ number: 1, name: "The One Where Monica Gets a Roommate" }] }];
    const { shows, decks, skipped } = lib.decksFromBundle(bundle, planned);
    expect(shows).toEqual([{ id: 431, name: "Friends", posterURL: "https://p", year: 1994, rank: 1 }]);
    expect(decks[0]).toMatchObject({ showId: 431, season: 1, episode: 1,
                                     title: "S01E01 · The One Where Monica Gets a Roommate" });
    expect(skipped).toEqual([]);
    expect(lib.decksFromBundle(bundle, []).skipped).toEqual(["Friends"]);
  });
});

describe("слова одного сериала", () => {
  it("слово, уже бывшее в другой серии, — ошибка", () => {
    const line = (term: string) => `${term} | /x/ | noun | р | п | e | A [${term}]. | Р. | П.`;
    const text = "# show: Friends\n## 1\n" + ["a", "b", "c", "d", "e"].map(line).join("\n")
      + "\n## 2\n" + ["f", "g", "h", "i", "A"].map(line).join("\n");
    expect(lib.parseWordsFile(text).errors).toEqual(["words.txt: «A» в серии 2 уже было в серии 1"]);
  });
});
