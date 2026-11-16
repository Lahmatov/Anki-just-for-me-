# Запуск и вкладки

## Sub-features

- Свежий запуск открывает «Сегодня» без заставки и знакомства (режим `-ui-testing`).
- Панель вкладок: «Сегодня», «Наборы», «Сериалы», «Настройки».

## How to get to it (user POV)

Запустить приложение. Учётная запись не нужна.

## Driving it with e2e

`tests/ios/launch.e2e.ts`. Локаторы: `screen.getByTestId('tab.today')`,
`tab.decks`, `tab.shows`, `tab.settings` (`App/Sources/Views/AppTabBar.swift`).
Живьём: `open_session` с целью `ios`, `observe`.

## Proof

Все четыре вкладки видны, «Сегодня» выбрана. Побочных эффектов нет.

## Charters

```
tabs-switching|ios|default|Starting on Today, switch between every tab several times and back; report a tab that does not open, shows the wrong screen or loses its scroll position
```

## Gotchas

- Первый экран дорисовывается до 20 с на медленном симуляторе: ждать `tab.today`
  с таймаутом, не нажимать раньше.
- Без `-ui-testing` приложение покажет заставку и знакомство — это не ошибка.
