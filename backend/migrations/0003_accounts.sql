-- Аккаунты: вход через Apple. Необязательный — без входа всё работает
-- как раньше, по устройству. Вход нужен, чтобы доступ (подписка или
-- промокод) следовал за человеком на все его телефоны.
--
-- Ни имени, ни e-mail, ни самого Apple ID здесь нет: только HMAC от
-- постоянного номера пользователя Apple (`sub`) — по нему аккаунт
-- находится при следующем входе, а из утёкшей базы номер не восстановить.
CREATE TABLE accounts (
    id                 TEXT PRIMARY KEY,
    apple_sub_hash     TEXT NOT NULL UNIQUE,
    -- Токен обновления Apple, зашифрованный AES-GCM. Нужен ровно для одного:
    -- при удалении аккаунта отозвать вход у Apple — это требование App Store.
    refresh_token_enc  TEXT,
    entitlement_id     TEXT,
    created_at         INTEGER NOT NULL,
    last_seen_at       INTEGER NOT NULL
);
CREATE INDEX accounts_last_seen ON accounts(last_seen_at);

ALTER TABLE devices ADD COLUMN account_id TEXT;
CREATE INDEX devices_account ON devices(account_id);
