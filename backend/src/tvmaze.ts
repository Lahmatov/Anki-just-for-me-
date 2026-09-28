import { ApiError } from "./http";
import type { Deps } from "./env";

/**
 * Серия из TVMaze — глазами сервера.
 *
 * Название и описание серии сервер берёт сам, а не из запроса: клиент
 * присылает только номера. Так «описание» нельзя подменить инструкцией
 * для модели, а запрос о несуществующей серии просто не пройдёт.
 */
export interface EpisodeFacts {
  showId: number;
  season: number;
  episode: number;
  showName: string;
  name: string;
  summary: string;
}

const HOST = "https://api.tvmaze.com";
const CACHE_SECONDS = 7 * 86_400;

export async function episodeFacts(
  db: D1Database, deps: Deps, showId: number, season: number, episode: number,
): Promise<EpisodeFacts> {
  const now = deps.now();
  const cached = await db.prepare(
    `SELECT show_name, name, summary, fetched_at FROM episode_cache
     WHERE show_id = ? AND season = ? AND episode = ?`,
  ).bind(showId, season, episode).first<{
    show_name: string; name: string; summary: string; fetched_at: number;
  }>();
  if (cached && now - cached.fetched_at < CACHE_SECONDS) {
    return { showId, season, episode, showName: cached.show_name, name: cached.name,
             summary: cached.summary };
  }

  const [show, item] = await Promise.all([
    getJSON<{ name?: string }>(deps, `${HOST}/shows/${showId}`),
    getJSON<{ name?: string; summary?: string | null }>(
      deps, `${HOST}/shows/${showId}/episodebynumber?season=${season}&number=${episode}`),
  ]);
  if (!show?.name || !item) throw new ApiError(404, "episode_not_found");

  const facts: EpisodeFacts = {
    showId, season, episode,
    showName: clip(show.name, 120),
    name: clip(item.name ?? "", 200),
    summary: clip(plainText(item.summary ?? ""), 3000),
  };
  await db.prepare(
    `INSERT INTO episode_cache (show_id, season, episode, show_name, name, summary, fetched_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(show_id, season, episode) DO UPDATE SET show_name = excluded.show_name,
       name = excluded.name, summary = excluded.summary, fetched_at = excluded.fetched_at`,
  ).bind(showId, season, episode, facts.showName, facts.name, facts.summary, now).run();
  return facts;
}

async function getJSON<T>(deps: Deps, url: string): Promise<T | null> {
  let response: Response;
  try {
    response = await deps.fetch(url, { headers: { accept: "application/json" } });
  } catch {
    throw new ApiError(502, "tvmaze_unavailable");
  }
  if (response.status === 404) return null;
  if (!response.ok) throw new ApiError(502, "tvmaze_unavailable");
  return await response.json() as T;
}

export function plainText(html: string): string {
  let text = html.replace(/<br\s*\/?>|<\/p>/gi, "\n").replace(/<[^>]+>/g, "");
  // &amp; — последним, иначе «&amp;lt;» раскодировался бы дважды.
  const entities: [string, string][] = [["&quot;", "\""], ["&#39;", "'"], ["&apos;", "'"],
    ["&nbsp;", " "], ["&lt;", "<"], ["&gt;", ">"], ["&#8217;", "’"], ["&amp;", "&"]];
  for (const [entity, value] of entities) text = text.split(entity).join(value);
  return text.split("\n").map((line) => line.replace(/[ \t]+/g, " ").trim())
    .filter((line) => line.length > 0).join("\n");
}

function clip(text: string, max: number): string {
  return text.length > max ? text.slice(0, max) : text;
}

export function episodeCode(season: number, episode: number): string {
  return `S${String(season).padStart(2, "0")}E${String(episode).padStart(2, "0")}`;
}
