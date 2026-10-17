import { readdirSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

/**
 * Миграции только расширяют схему (P-71): сервер обновляется раньше или
 * позже базы, и старый код должен работать с новой схемой, а новый — с
 * той, где миграция ещё не прошла. Удалять и переименовывать — в два
 * релиза: сначала код перестаёт читать, потом отдельная миграция убирает
 * (с пометкой `-- contract:` и причиной). Правила — docs/server-updates.md.
 */
const DIR = new URL("../migrations/", import.meta.url);
const files = readdirSync(DIR).filter((name) => name.endsWith(".sql")).sort();

function sql(name: string): string {
  // Комментарии не считаются: в них можно писать что угодно.
  return readFileSync(new URL(name, DIR), "utf8").replace(/--.*$/gm, "");
}

describe("миграции", () => {
  it("пронумерованы подряд без пропусков и повторов", () => {
    const numbers = files.map((name) => Number(name.slice(0, 4)));
    expect(numbers).toEqual(numbers.map((_, index) => index + 1));
  });

  it("каждая — с объяснением, зачем она", () => {
    for (const name of files) {
      expect(readFileSync(new URL(name, DIR), "utf8").trimStart().startsWith("--"), name).toBe(true);
    }
  });

  it("ничего не удаляют и не переименовывают без пометки contract", () => {
    const destructive = /\b(DROP\s+(TABLE|COLUMN|INDEX)|RENAME\s+(TO|COLUMN)|ALTER\s+COLUMN)\b/i;
    for (const name of files) {
      const raw = readFileSync(new URL(name, DIR), "utf8");
      if (/^--\s*contract:/m.test(raw)) continue;
      expect(destructive.test(sql(name)), name).toBe(false);
    }
  });

  it("новый обязательный столбец — только со значением по умолчанию", () => {
    for (const name of files) {
      for (const statement of sql(name).split(";")) {
        if (!/ALTER\s+TABLE\s+\w+\s+ADD\s+COLUMN/i.test(statement)) continue;
        if (/NOT\s+NULL/i.test(statement)) {
          expect(/DEFAULT/i.test(statement), `${name}: ${statement.trim()}`).toBe(true);
        }
      }
    }
  });
});
