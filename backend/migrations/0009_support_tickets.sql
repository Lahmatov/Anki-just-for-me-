-- Обращения в поддержку из приложения (P-72). Ответ пишется сюда же и
-- виден человеку в приложении — переписка не теряется в почте, а номер
-- обращения связывает письмо, телефон и запись на сервере.
--
-- Владелец — устройство (и аккаунт, если вошёл): так обращения переживают
-- смену телефона у вошедших и уходят вместе с данными при удалении.
-- Срок хранения — год после последнего изменения (retention.ts).
CREATE TABLE support_tickets (
    id           TEXT PRIMARY KEY,
    device_id    TEXT NOT NULL,
    account_id   TEXT,
    category     TEXT NOT NULL,
    message      TEXT NOT NULL,
    contact      TEXT,
    diagnostics  TEXT,
    status       TEXT NOT NULL DEFAULT 'open',
    reply        TEXT,
    created_at   INTEGER NOT NULL,
    updated_at   INTEGER NOT NULL
);
CREATE INDEX support_tickets_device ON support_tickets(device_id, created_at);
CREATE INDEX support_tickets_account ON support_tickets(account_id, created_at);
CREATE INDEX support_tickets_status ON support_tickets(status, created_at);
