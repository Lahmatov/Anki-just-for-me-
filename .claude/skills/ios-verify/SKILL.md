---
name: ios-verify
description: Как проверить изменения iOS-приложения Recap без Xcode под рукой — статические проверки, тесты Core и сервера, сборка и UI-тесты в GitHub Actions, прогон на устройствах (iPhone, iPad, iPhone Duo), чтение логов упавшей сборки. Использовать перед каждым коммитом и когда нужно узнать, собирается ли приложение.
---

# Проверка изменений

Идея из [iOS Claude Code setup](https://gist.github.com/joelklabo/6df9fa603bec3478dec7efc17ea44596):
сначала понять проект (схемы, цели, тесты), затем держать короткие
повторяемые команды для сборки и тестов. Здесь Xcode обычно нет (облачная
Linux-машина), поэтому сборка — в GitHub Actions, а локально — то, что
работает без macOS.

## Карта проекта

| Что | Где | Чем проверяется |
|---|---|---|
| Проект Xcode | генерируется из `project.yml` (XcodeGen) | CI: `xcodegen generate` |
| Схема | `AJFM` (приложение), цели `AJFM`, `AJFMWidget`, `AJFMTests`, `AJFMUITests` | CI |
| Ядро | `Core/` — Swift-пакет `AJFMCore` | `cd Core && swift test` (macOS/Linux со Swift) |
| Тесты базы | `App/Tests/` | CI, ⌘U в Xcode |
| UI-тесты | `App/UITests/` | CI и Devices |
| Сервер | `backend/` | `cd backend && npm test && npm run typecheck` |
| Правила | `tools/lint.py`, `tools/release_check.py` | локально |

## Перед каждым коммитом (локально)

```sh
python3 tools/lint.py                     # скобки, импорты, public init, дубликаты типов,
                                          # кириллица вне tr(), секреты в журнале, тексты App Store
(cd backend && npm test && npm run typecheck)   # если трогал backend/ или docs/legal
(cd Core && swift test)                   # если есть swift; иначе — ждать CI
```

Lint не заменяет компилятор. Перечитай свой diff глазами того, кто будет
компилировать: доступность `#available`, `@MainActor` у `@Observable`,
импорты фреймворков, точные имена API (проверяй по документации Apple —
`developer.apple.com/tutorials/data/documentation/<framework>/<symbol>.json`).

## После пуша (GitHub Actions)

- **CI** (`.github/workflows/ci.yml`): статические проверки, сервер, `swift test`,
  сборка приложения и тесты на симуляторе. Около 20–30 минут.
- **Devices** (`.github/workflows/devices.yml`): UI-тесты и скриншоты на 18
  устройствах: iPhone от SE до Pro Max, iPad, крупный шрифт, iPhone Duo
  (Xcode 27, отдельная машина). Запускается при изменениях в `App/`,
  `Core/Sources/`, `project.yml`. Скриншоты — в артефактах прогона.
- Новый пуш в ту же ветку отменяет незаконченный прогон — не пушь мелочи
  подряд, если ждёшь результата.

Статус и логи без `gh`-клиента:

```sh
gh api "repos/lahmatov/Anki-just-for-me-/actions/runs?head_sha=$(git rev-parse HEAD)"
gh api "repos/lahmatov/Anki-just-for-me-/actions/runs/<run_id>/jobs"
```

Лог задачи — инструмент `mcp__github__get_job_logs` (`job_id`, `return_content: true`,
`tail_lines`). Ошибки компиляции ищи по `error:`, падения тестов — по
`Test Case .* failed`.

## Разбор падения

1. Сначала прочитать лог, найти первую `error:` — остальные часто следствие.
2. Воспроизвести локально, что можно (lint, Core, сервер).
3. Чинить причину, а не тест; тест не отключать и не пропускать.
4. «Нестабильный тест» — не причина: тайминги, прокрутка с инерцией,
   клавиатура поверх кнопки — чинить в тесте или в раскладке.
5. Один проверенный пуш лучше трёх наугад.

## iPhone Duo

Симулятор — только Xcode 27.1+ с iOS 27.1. Строка Duo в Devices сама выбирает
новейший **выпуск** Xcode 27 на машине `xcode-27`, в котором есть это
устройство (беты — после выпусков: у беты своя iOS, которой на машине обычно нет), берёт iOS не ниже 27.1
(`ios: "27.1"` в матрице), при нехватке докачивает её и пропускается
с предупреждением, если симулятора всё равно нет. Складывание в симуляторе — вручную (Device Hub); в CI
проверяется то состояние, в котором симулятор загрузился.

## Документация рядом с кодом

Решения — `docs/decisions.md` (P-номер), чек-лист выпуска — `docs/launch.md`.
Новый навык или правило проекта — сюда, в `.claude/skills/`, и строкой в `CLAUDE.md`.
