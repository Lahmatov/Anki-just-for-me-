# Устройство на сервере

## Sub-features

- `GET /v1/health` — база отвечает, номер API, последняя миграция, хранилище бэкапов.
- `POST /v1/devices` — регистрация телефона, выдаёт токен (201); не больше 20 в час с одного IP.
- `GET /v1/me` — профиль: план, единицы, вход, код поддержки.
- `DELETE /v1/me` — забыть устройство; токен больше не принимается (401).

## How to get to it (user POV)

Приложение ходит сюда само при первом запуске и в «Профиле». В e2e — цель `api`,
`app.baseUrl` — адрес локального сервера.

## Driving it with e2e

`tests/api/devices.e2e.ts` — `fetch` и точные проверки JSON;
`tests/api/health-agent.e2e.ts` (тег `agent`) — агент читает `/v1/health` в
браузере и судит по смыслу. Новые маршруты — по таблице в `backend/src/app.ts`
(`handle`), формы ответов — в `backend/test/*.test.ts`.

## Proof

Статус и JSON ответа; побочный эффект — строки в таблицах `devices` и др. в
локальной D1 (`e2e/.wrangler-e2e/`, см. SKILL.md).

## Charters

```
api-unauth|api|default|Starting at /v1/health, open /v1/me, /v1/catalog, /v1/backups and an unknown path without a token; report responses that leak internal detail or use the wrong status
```

## Gotchas

- Каталог локально пуст (`{"shows":[]}`): его наполняет `npm run catalog`, не миграции.
- Маршруты модели (`/v1/deck`, `/v1/lesson`, `/v1/help`, `/v1/discuss`) с ключом-заглушкой
  отвечают ошибкой — их проверяют юнит-тесты `backend/test/` с поддельной моделью.
- Регистрация ограничена 20 в час на IP: база стирается на каждом прогоне, но
  один прогон с повторами не должен регистрировать больше.
