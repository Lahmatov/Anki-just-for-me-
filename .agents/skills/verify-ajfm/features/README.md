# Карта функций

Одна страница на функцию, с точки зрения человека. Тесты — в `e2e/tests/`.
Экранов больше (уроки, сериалы и пересказ, облачная копия, награды, помощник
Мончик); карта растёт, когда изменение их касается.

| Функция | Где | Тест | Статус |
|---|---|---|---|
| [Запуск и вкладки](launch.md) | приложение, «Сегодня» | `tests/ios/launch.e2e.ts` | tested (CI macOS) |
| [Стартовый набор и занятие](study.md) | «Сегодня» → занятие | `tests/ios/study.e2e.ts`, `tests/ios/agent.e2e.ts` | tested (CI macOS) |
| [Документы в профиле](profile.md) | Настройки → Профиль | `tests/ios/profile.e2e.ts`, `tests/ios/agent.e2e.ts` | tested (CI macOS) |
| [Устройство на сервере](server-devices.md) | `/v1/health`, `/v1/devices`, `/v1/me` | `tests/api/devices.e2e.ts`, `tests/api/health-agent.e2e.ts` | tested |
| Уроки | «Сегодня» → `today.lessons` | — | untested |
| Сериалы и пересказ | вкладка `tab.shows` | — | untested |
| Облачная копия | Профиль → облако (`cloud.toggle`) | — | untested |
