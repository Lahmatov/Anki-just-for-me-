import type { Language } from "./prompts";

/**
 * Каталог: готовые наборы к первым сезонам популярных сериалов.
 *
 * Наборы собраны заранее (scripts/build-catalog.ts) сразу на трёх языках,
 * отдаются из базы и не тратят лимит: модель уже отработала один раз
 * за всех. Формат слова в каталоге — с переводами на все языки.
 */
export interface CatalogNote {
  term: string;
  ipa?: string;
  partOfSpeech?: string;
  translation: Record<Language, string>;
  example?: string;
  exampleTranslation?: Partial<Record<Language, string>>;
  cloze?: string;
  note?: Partial<Record<Language, string>>;
}

export async function listShows(db: D1Database) {
  const rows = await db.prepare(
    `SELECT s.show_id AS showId, s.name, s.poster_url AS posterUrl, s.year,
            COUNT(d.episode) AS decks
     FROM catalog_shows s LEFT JOIN catalog_decks d ON d.show_id = s.show_id
     GROUP BY s.show_id ORDER BY s.rank`,
  ).all();
  return rows.results;
}

export async function showDecks(db: D1Database, showId: number) {
  const rows = await db.prepare(
    `SELECT season, episode, title FROM catalog_decks WHERE show_id = ?
     ORDER BY season, episode`,
  ).bind(showId).all();
  return rows.results;
}

export async function catalogNotes(
  db: D1Database, showId: number, season: number, episode: number,
): Promise<CatalogNote[] | null> {
  const row = await db.prepare(
    "SELECT deck_json FROM catalog_decks WHERE show_id = ? AND season = ? AND episode = ?",
  ).bind(showId, season, episode).first<{ deck_json: string }>();
  if (!row) return null;
  try {
    const parsed = JSON.parse(row.deck_json) as { notes?: CatalogNote[] };
    return Array.isArray(parsed.notes) ? parsed.notes : null;
  } catch {
    return null;
  }
}

/** Слова каталога на языке ученика — в формате приложения. */
export function localizeNotes(notes: CatalogNote[], language: Language, knownTerms: string[]) {
  const known = new Set(knownTerms.map((term) => term.toLowerCase()));
  return notes
    .filter((note) => !known.has(note.term.toLowerCase()))
    // Слово без перевода на язык человека пропускаем, а не подставляем
    // английское толкование: иначе в русском наборе оказывались английские
    // фразы, и на карточке «Выбери перевод» ответ угадывался по языку.
    .filter((note) => Boolean(note.translation[language]?.trim()))
    .map((note) => ({
      term: note.term,
      translation: note.translation[language]!,
      ...(note.ipa ? { ipa: note.ipa } : {}),
      ...(note.partOfSpeech ? { partOfSpeech: note.partOfSpeech } : {}),
      ...(note.example ? { example: note.example } : {}),
      ...(language !== "en" && note.exampleTranslation?.[language]
        ? { exampleTranslation: note.exampleTranslation[language] } : {}),
      ...(note.cloze ? { cloze: note.cloze } : {}),
      ...(note.note?.[language] ? { note: note.note[language] } : {}),
    }));
}
