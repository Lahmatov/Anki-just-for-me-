import { describe, expect, it } from "vitest";
import { movieLabel, parseMovie } from "../src/movies";

const ITEM = {
  kind: "feature-movie", trackId: 42, trackName: " Heat ", releaseDate: "1995-12-15T08:00:00Z",
  longDescription: "<p>Cops &amp; robbers.</p>",
  artworkUrl100: "https://is1-ssl.mzstatic.com/image/thumb/a/b/100x100bb.jpg",
};

describe("разбор фильма из каталога Apple", () => {
  it("берёт название, год, описание и постер крупнее", () => {
    expect(parseMovie(ITEM, 42)).toEqual({
      movieId: 42, title: "Heat", year: 1995, summary: "Cops & robbers.",
      artwork: "https://is1-ssl.mzstatic.com/image/thumb/a/b/600x600bb.jpg",
    });
  });

  it("чужой номер в ответе — не тот фильм", () => {
    expect(parseMovie(ITEM, 43)).toBeNull();
  });

  it("не фильм и пустое название — null", () => {
    expect(parseMovie({ ...ITEM, kind: "tv-episode" }, 42)).toBeNull();
    expect(parseMovie({ ...ITEM, trackName: "  " }, 42)).toBeNull();
    expect(parseMovie(undefined, 42)).toBeNull();
  });

  it("без даты, описания и постера — фильм всё равно есть", () => {
    const bare = parseMovie({ kind: "feature-movie", trackId: 42, trackName: "Heat" }, 42);
    expect(bare).toEqual({ movieId: 42, title: "Heat", year: null, summary: "", artwork: null });
  });

  it("постер не по https не берётся", () => {
    expect(parseMovie({ ...ITEM, artworkUrl100: "http://x/100x100bb.jpg" }, 42)?.artwork).toBeNull();
  });

  it("короткое описание — если длинного нет", () => {
    const item = { ...ITEM, longDescription: undefined, shortDescription: "Short." };
    expect(parseMovie(item, 42)?.summary).toBe("Short.");
  });

  it("длинное название и описание обрезаются", () => {
    const parsed = parseMovie({ ...ITEM, trackName: "x".repeat(500), longDescription: "y".repeat(9000) }, 42);
    expect(parsed?.title).toHaveLength(120);
    expect(parsed?.summary).toHaveLength(3000);
  });

  it("год вне разумного — нет года", () => {
    expect(parseMovie({ ...ITEM, releaseDate: "0001-01-01" }, 42)?.year).toBeNull();
    expect(parseMovie({ ...ITEM, releaseDate: "garbage" }, 42)?.year).toBeNull();
  });

  it("подпись — с годом, если он есть", () => {
    expect(movieLabel({ movieId: 1, title: "Heat", year: 1995, summary: "", artwork: null })).toBe("Heat (1995)");
    expect(movieLabel({ movieId: 1, title: "Heat", year: null, summary: "", artwork: null })).toBe("Heat");
  });
});
