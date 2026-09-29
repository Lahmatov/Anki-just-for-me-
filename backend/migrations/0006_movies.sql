-- Фильмы рядом с сериалами. Сведения о фильме (название, год, описание,
-- постер) сервер берёт сам из каталога Apple (iTunes Search API, без ключа),
-- а не из запроса: клиент присылает только номер фильма — как с сериями
-- TVMaze. Кеш — чтобы не спрашивать Apple на каждый набор.
CREATE TABLE movie_cache (
    movie_id    INTEGER PRIMARY KEY,
    title       TEXT NOT NULL,
    year        INTEGER,
    summary     TEXT NOT NULL,
    artwork     TEXT,
    fetched_at  INTEGER NOT NULL
);
