-- Срок жизни счётчиков частоты. По `win` его не понять: окна разной
-- длины (минута, час, сутки). Ночная чистка удаляет счётчики, чьё окно
-- уже закончилось, — ключи содержат номер устройства или хеш IP, и
-- держать их дольше, чем они работают, незачем (GDPR, ст. 5(1)(e)).
ALTER TABLE rate_limits ADD COLUMN expires_at INTEGER NOT NULL DEFAULT 0;
CREATE INDEX rate_limits_expires ON rate_limits(expires_at);

-- Для чистки неактивных устройств.
CREATE INDEX devices_last_seen ON devices(last_seen_at);
CREATE INDEX usage_log_created ON usage_log(created_at);
