---
name: verify-ajfm
description: Запустить, проверить и доказать изменение Recap (AJFM) так, как его увидит человек, через e2e — приложение на симуляторе iOS (только macOS / CI «E2E») и сервер Recap по HTTP (работает и в облачной Linux-машине). Использовать перед тем, как заявить, что изменение экрана или API работает, когда просят проверить экран или ответ сервера, и для поиска ошибок (bug bash).
---

# Проверка Recap через e2e

Сначала навык e2e: `cd e2e && npx e2e guide` (темы: `setup`, `writing-tests`,
`mcp`, `running`, `debugging`, `bug-bash`). Здесь — только то, что верно для
этого проекта. Всё e2e живёт в подпакете `e2e/`: конфиг `e2e/e2e.config.ts`,
тесты `e2e/tests/**/*.e2e.ts`; команды запускаются из `e2e/`.

Цели конфига:

| Цель | Что | Где работает |
|---|---|---|
| `api` | сервер `backend/` — настоящий Worker в локальном workerd (`wrangler dev`), D1 — локальный SQLite | Linux и macOS; здесь, в облачной машине |
| `ios` | приложение `com.lahmatov.ajfm` на симуляторе iOS | только macOS с Xcode: CI-задача «E2E — приложение (симулятор iOS)» |

В облачной Linux-машине симулятора нет: изменения экранов доказываются
прогоном workflow `E2E` (`.github/workflows/e2e.yml`) после пуша, сервер —
локально.

## Запуск

Один раз: `npm ci --prefix backend && npm ci --prefix e2e`.

- **api.** Сервер стартует сам: `app.command` в конфиге запускает
  `node scripts/backend.mjs {port}` на свободном порту. Скрипт стирает
  `e2e/.wrangler-e2e/`, применяет все миграции (`wrangler d1 migrations apply
  --local`) и поднимает `wrangler dev`; готовность — `GET /v1/health` отвечает.
  Секреты — заглушки (`PROMO_PEPPER` локальный, ключ Anthropic не настоящий):
  маршруты, которые зовут модель (`/v1/deck`, `/v1/lesson`, `/v1/help`…), здесь
  не проверить. Лог сервера — `e2e/.e2e/logs/backend.log`. Браузер нужен
  только агентским шагам: `npx e2e-web install chromium`. Если загрузка
  браузера закрыта прокси, укажи `PLAYWRIGHT_BROWSERS_PATH` на каталог с уже
  установленным Chromium нужной ревизии (имя `chromium_headless_shell-<rev>`).
- **ios.** Движок ничего не устанавливает. Нужен загруженный симулятор iPhone
  (iOS 26+) с установленной Debug-сборкой:
  ```sh
  xcodegen generate
  xcodebuild build -project AJFM.xcodeproj -scheme AJFM -configuration Debug \
    -destination "generic/platform=iOS Simulator" -derivedDataPath build CODE_SIGNING_ALLOWED=NO
  xcrun simctl boot <UDID>; xcrun simctl bootstatus <UDID> -b
  xcrun simctl install <UDID> build/Build/Products/Debug-iphonesimulator/AJFM.app
  ```
  Каждый тест начинается с `app.open()` — свежий запуск с
  `-ui-testing -AppleLanguages (en) -AppleLocale en_US`: база в памяти,
  настройки сброшены, без заставки и знакомства
  (`App/Sources/Services/UITesting.swift`). Демо-данных нет — стартовый набор
  добавляется кнопкой `today.starter`.

## Doctor

```sh
cd e2e
npx e2e list                                  # конфиг грузится, 10 пар тест-цель; ничего не запускает
npx e2e run --target api --exclude-tag agent  # сервер стартует, 4 теста API; exit 0
npx e2e doctor --target ios                   # на Mac: Xcode, симулятор, agent-device
npx e2e run tests/ios/launch.e2e.ts           # на Mac: приложение открывается на «Сегодня»
```

`list` падает — конфиг или зависимости. `APP_UNREACHABLE` у `api` — смотри
`.e2e/logs/backend.log` (нет `backend/node_modules`, сломанная миграция).
`BROWSER_INSTALL_FAILED` — см. браузер выше. На Linux `doctor` честно
проваливает `[ios] device`: это ожидаемо. Запускай Doctor первым, если что-то
выглядит не так.

## Действие

- **Живьём** через `e2e mcp` (тема `mcp`), если сервер e2e подключён к
  клиенту: `open_session` с целью `api` или `ios`, `observe`, `locate` перед
  тем, как писать локатор. Учётных записей и инструментов проекта нет.
- **Скриптом.** Тест под `e2e/tests/`. API — только фикстура `app` и `fetch`
  на `app.baseUrl` (тема `writing-tests`), `describe(..., { platforms: ['web'] })`.
  Приложение — `test`/`describe` из `@e2e-dev/mobile`,
  `{ platforms: ['ios'] }`, элементы по `screen.getByTestId('<id>')`:
  `accessibilityIdentifier` уже есть на вкладках (`tab.today|decks|shows|settings`),
  кнопках «Сегодня» (`today.starter`, `today.study`), сессии
  (`session.progress`, `grade.<n>`), профиле (`settings.profile`, `docs.terms|privacy|licenses`)
  и др. — `grep -rn accessibilityIdentifier App/Sources`. Тексты есть на трёх
  языках, поэтому текст проверяй только на английском (он задан аргументами
  запуска). Нет id — добавь `.accessibilityIdentifier` в экран, поведение не меняя.
- **Агентские шаги** (`agent.act`, `agent.assert`) идут на Claude Code по
  подписке (`claudeCode({ model: 'sonnet' })` из `@e2e-dev/acp`): локально
  через вход `claude`, в CI через секрет `CLAUDE_CODE_OAUTH_TOKEN`. Такие тесты
  помечены тегом `agent`; без входа запускай с `--exclude-tag agent`.
  Каждый агентский тест заканчивается точной проверкой или `agent.assert`.

## Доказательства

Каждый прогон пишет `e2e/.e2e/report.json`; у упавшего теста —
`e2e/.e2e/results/<тест>/trace.md` (экран в момент падения), `--trace on`
даёт трейс и прошедшим, `--video` пишет видео попытки, `app.screenshot('<имя>')`
сохраняет кадр. Следующий прогон чистит `.e2e/results/`, поэтому доказательство,
которое должно пережить его, гоняй с `--output .e2e/proof/<имя>`. В CI всё это —
артефакты `e2e-api` и `e2e-ios` прогона workflow `E2E`.

Стандарт доказательства: путь человека (вкладка, кнопка, маршрут API), а не
внутренние сеттеры; видно действие и состояние после него; побочные эффекты —
в хранилище: у сервера это локальная D1 в `e2e/.wrangler-e2e/` (SQLite,
живёт до следующего прогона; `wrangler d1 execute recap --local --persist-to
../e2e/.wrangler-e2e --command "SELECT …"` из `backend/`), у приложения база в
памяти — побочные эффекты видны только на экране. Модель на сервере не
вызывается — не выдавай заглушку за проверку `/v1/deck` и подобных.

## Bug bash

`e2e explore` работает только на встроенном агенте с моделью AI SDK — исполнитель
Claude Code по подписке он не принимает (`MODEL_UNAVAILABLE`). Для bug bash
создай неотслеживаемый `e2e/e2e.bugbash.config.ts`: импортирует
`e2e.config.ts`, заменяет `agents` на модель с ключом (например
`anthropic('<id>')` из `@ai-sdk/anthropic` с `ANTHROPIC_API_KEY`), добавляет
`tests/bugbash/**` и персоны `skeptic`/`fuzzer`; в `context` — что здесь не
ошибка (заглушки секретов, пустой каталог, отказ маршрутов модели). Хартии —
в [features/](features/), строками `slug|target|agent|charter` (тема
`bug-bash`, шаг 3). Вывод — `e2e/.e2e/bugbash/` (внутри игнорируемого `.e2e/`).
Цель `ios` — один симулятор, по одному исследователю за раз. Находка —
ошибка, только когда `tests/bugbash/<slug>.e2e.ts` падает на ней (тема
`bug-bash`, шаг 6). Сейчас bug bash не проверен: ключа модели нет.

## Уборка

Сервер, который запустил раннер, раннер и останавливает; `close_session`
останавливает запущенный сессией. Свой `wrangler dev` останавливай по pid,
никогда `pkill node`. Симулятор, загруженный тобой, — `xcrun simctl shutdown <UDID>`.
`e2e/.wrangler-e2e/` можно удалить (скрипт и так стирает его при старте).
Не трогай `.e2e/results/`, `.e2e/proof/`, `.e2e/report.json` — это доказательства;
всё это в `.gitignore`.

## Помощники

`e2e/scripts/backend.mjs` — поднимает сервер для цели `api`; вызывает его
раннер, руками: `node e2e/scripts/backend.mjs 8787`. Остальное — CLI e2e.
