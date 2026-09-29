-- Облачный бэкап на своём сервере вместо Neon: человеку не нужно заводить
-- базу и вставлять строку подключения — копия уходит туда же, куда и
-- запросы наборов.
--
-- Владелец — аккаунт (если вошёл через Apple) или устройство. Только
-- аккаунт переживает смену телефона: на новом телефоне копии устройства
-- не найти, поэтому при входе они переходят аккаунту.
--
-- Снимок режется на части: у D1 предел строки — 2 МБ, а база со статистикой
-- за годы больше. Части зашифрованы AES-GCM ключом, выведенным из секрета
-- сервера и номера снимка: утёкшая база не выдаёт словари и прогресс.
CREATE TABLE backups (
    id            TEXT PRIMARY KEY,
    owner         TEXT NOT NULL,
    device_label  TEXT NOT NULL,
    note_count    INTEGER NOT NULL,
    mature_words  INTEGER NOT NULL,
    size          INTEGER NOT NULL,
    chunks        INTEGER NOT NULL,
    created_at    INTEGER NOT NULL
);
CREATE INDEX backups_owner ON backups(owner, created_at);

CREATE TABLE backup_chunks (
    backup_id  TEXT NOT NULL,
    seq        INTEGER NOT NULL,
    data       TEXT NOT NULL,
    PRIMARY KEY (backup_id, seq)
);
