-- Схема сервера Recap (Cloudflare D1, это SQLite).
--
-- Здесь нет ни слов пользователей, ни текстов пересказов: база знает
-- только устройство, его доступ и сколько он потратил. Содержимое запросов
-- к ИИ не хранится вовсе — ни в базе, ни в журнале.

-- Устройство. Токен хранится только хешем: утечка базы не даёт войти.
CREATE TABLE devices (
    id              TEXT PRIMARY KEY,
    token_hash      TEXT NOT NULL UNIQUE,
    entitlement_id  TEXT REFERENCES entitlements(id),
    created_at      INTEGER NOT NULL,
    last_seen_at    INTEGER NOT NULL
);
CREATE INDEX devices_entitlement ON devices(entitlement_id);

-- Доступ: подписка (общая для устройств одной покупки) или промокод.
-- Единицы — токены, где выход весит как пять входов (так же соотносятся
-- цены модели).
CREATE TABLE entitlements (
    id                       TEXT PRIMARY KEY,
    kind                     TEXT NOT NULL CHECK (kind IN ('promo', 'subscription')),
    units_per_period         INTEGER NOT NULL,
    used                     INTEGER NOT NULL DEFAULT 0,
    period_start             INTEGER NOT NULL,
    period_end               INTEGER NOT NULL,
    original_transaction_id  TEXT UNIQUE,
    product_id               TEXT,
    updated_at               INTEGER NOT NULL
);

-- Брони единиц на время запроса к модели. Запись, а не счётчик: если
-- запрос оборвётся на полпути, бронь не повиснет навсегда — через десять
-- минут она просто перестаёт учитываться.
CREATE TABLE reservations (
    id              TEXT PRIMARY KEY,
    entitlement_id  TEXT NOT NULL,
    amount          INTEGER NOT NULL,
    created_at      INTEGER NOT NULL
);
CREATE INDEX reservations_entitlement ON reservations(entitlement_id, created_at);

-- Промокоды — только HMAC с секретным перцем: из базы их не восстановить.
CREATE TABLE promo_codes (
    hash         TEXT PRIMARY KEY,
    batch        TEXT NOT NULL,
    days         INTEGER NOT NULL,
    units        INTEGER NOT NULL,
    created_at   INTEGER NOT NULL,
    expires_at   INTEGER,
    redeemed_at  INTEGER,
    redeemed_by  TEXT
);

-- Серии, к которым устройство уже получило слова. Только по ним разрешён
-- разговор с Мончиком — так ИИ нельзя превратить в чат на любую тему.
CREATE TABLE device_episodes (
    device_id   TEXT NOT NULL,
    show_id     INTEGER NOT NULL,
    season      INTEGER NOT NULL,
    episode     INTEGER NOT NULL,
    created_at  INTEGER NOT NULL,
    PRIMARY KEY (device_id, show_id, season, episode)
);

-- Кеш серий из TVMaze: описание берётся сервером, а не присылается
-- клиентом, — подменить «описание» на произвольный текст нельзя.
CREATE TABLE episode_cache (
    show_id     INTEGER NOT NULL,
    season      INTEGER NOT NULL,
    episode     INTEGER NOT NULL,
    show_name   TEXT NOT NULL,
    name        TEXT NOT NULL,
    summary     TEXT NOT NULL,
    fetched_at  INTEGER NOT NULL,
    PRIMARY KEY (show_id, season, episode)
);

-- Готовый каталог: топ сериалов и наборы слов к первому сезону.
CREATE TABLE catalog_shows (
    show_id     INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    poster_url  TEXT,
    year        INTEGER,
    rank        INTEGER NOT NULL
);

CREATE TABLE catalog_decks (
    show_id     INTEGER NOT NULL,
    season      INTEGER NOT NULL,
    episode     INTEGER NOT NULL,
    title       TEXT NOT NULL,
    deck_json   TEXT NOT NULL,
    PRIMARY KEY (show_id, season, episode)
);

-- Счётчики частоты запросов: окно фиксированной длины на ключ.
CREATE TABLE rate_limits (
    key      TEXT PRIMARY KEY,
    win      INTEGER NOT NULL,
    count    INTEGER NOT NULL
);

-- Расход без содержимого: сколько и на что, чтобы видеть стоимость.
CREATE TABLE usage_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    entitlement_id  TEXT NOT NULL,
    device_id       TEXT NOT NULL,
    kind            TEXT NOT NULL,
    input_tokens    INTEGER NOT NULL,
    output_tokens   INTEGER NOT NULL,
    units           INTEGER NOT NULL,
    created_at      INTEGER NOT NULL
);
CREATE INDEX usage_log_entitlement ON usage_log(entitlement_id, created_at);
