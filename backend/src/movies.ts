import { ApiError } from "./http";
import { plainText } from "./tvmaze";
import type { Deps } from "./env";

/**
 * Фильм из каталога Apple — глазами сервера.
 *
 * У TVMaze фильмов нет, а iTunes Search API открыт без ключа и знает почти
 * всё, что выходило в прокате. Как и с сериями, клиент присылает только
 * номер, а название и описание сервер берёт сам: так в промпт не попадёт
 * «название фильма», которое на деле инструкция для модели.
 */
export interface MovieFacts {
  movieId: number;
  title: string;
  year: number | null;
  summary: string;
  artwork: string | null;
}

const LOOKUP = "https://itunes.apple.com/lookup";
const CACHE_SECONDS = 30 * 86_400;

export function isMovie(facts: object): facts is MovieFacts {
  return "movieId" in facts;
}

export async function movieFacts(db: D1Database, deps: Deps, movieId: number): Promise<MovieFacts> {
  const now = deps.now();
  const cached = await db.prepare(
    "SELECT title, year, summary, artwork, fetched_at FROM movie_cache WHERE movie_id = ?",
  ).bind(movieId).first<{ title: string; year: number | null; summary: string; artwork: string | null;
                          fetched_at: number }>();
  if (cached && now - cached.fetched_at < CACHE_SECONDS) {
    return { movieId, title: cached.title, year: cached.year, summary: cached.summary,
             artwork: cached.artwork };
  }

  let response: Response;
  try {
    response = await deps.fetch(`${LOOKUP}?id=${movieId}&country=US&entity=movie`,
      { headers: { accept: "application/json" } });
  } catch {
    throw new ApiError(502, "movies_unavailable");
  }
  if (!response.ok) throw new ApiError(502, "movies_unavailable");
  let payload: { results?: Record<string, unknown>[] };
  try {
    payload = await response.json() as typeof payload;
  } catch {
    throw new ApiError(502, "movies_unavailable");
  }
  const facts = parseMovie(payload.results?.[0], movieId);
  if (!facts) throw new ApiError(404, "movie_not_found");

  await db.prepare(
    `INSERT INTO movie_cache (movie_id, title, year, summary, artwork, fetched_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(movie_id) DO UPDATE SET title = excluded.title, year = excluded.year,
       summary = excluded.summary, artwork = excluded.artwork, fetched_at = excluded.fetched_at`,
  ).bind(movieId, facts.title, facts.year, facts.summary, facts.artwork, now).run();
  return facts;
}

/**
 * Разбор записи iTunes. Не фильм (песня, книга с тем же номером) — null:
 * набор к альбому по «номеру фильма» — это ошибка клиента, а не фильм.
 */
export function parseMovie(item: Record<string, unknown> | undefined, movieId: number): MovieFacts | null {
  if (!item || item.kind !== "feature-movie" || item.trackId !== movieId) return null;
  const title = typeof item.trackName === "string" ? item.trackName.trim() : "";
  if (!title) return null;
  const released = typeof item.releaseDate === "string" ? Number.parseInt(item.releaseDate.slice(0, 4), 10) : NaN;
  const description = typeof item.longDescription === "string" ? item.longDescription
    : typeof item.shortDescription === "string" ? item.shortDescription : "";
  const artwork = typeof item.artworkUrl100 === "string" && item.artworkUrl100.startsWith("https://")
    // Картинка 100×100 для постера мала; Apple отдаёт любой размер по имени.
    ? item.artworkUrl100.replace(/\/\d+x\d+bb\./, "/600x600bb.") : null;
  return {
    movieId,
    title: title.slice(0, 120),
    year: Number.isInteger(released) && released > 1880 && released < 2200 ? released : null,
    summary: plainText(description).slice(0, 3000),
    artwork,
  };
}

/** «Inception (2010)» — так фильм называется в наборе и в промпте. */
export function movieLabel(facts: MovieFacts): string {
  return facts.year ? `${facts.title} (${facts.year})` : facts.title;
}
