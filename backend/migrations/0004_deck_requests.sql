-- Запрос набора с номером от приложения: если телефон свернули и связь
-- оборвалась, повтор с тем же номером получает готовый набор, а не
-- второй платный вызов модели. Хранится сутки (retention.ts).
CREATE TABLE deck_requests (
    device_id   TEXT NOT NULL,
    request_id  TEXT NOT NULL,
    status      TEXT NOT NULL,          -- pending | done | failed
    response    TEXT,
    created_at  INTEGER NOT NULL,
    PRIMARY KEY (device_id, request_id)
);
