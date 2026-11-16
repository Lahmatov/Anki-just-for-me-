# Стартовый набор и занятие

## Sub-features

- На пустой базе «Сегодня» предлагает стартовый набор (`today.starter`).
- После него появляется «Study» (`today.study`), открывающая занятие.
- В занятии — полоса прогресса (`session.progress`), карточка, оценки
  (`grade.<n>`); панель вкладок спрятана.

## How to get to it (user POV)

«Сегодня» → «Starter deck» → «Study».

## Driving it with e2e

`tests/ios/study.e2e.ts` — точный путь; `tests/ios/agent.e2e.ts`
(«a study session shows a flashcard to recall») — `agent.assert`, что на
экране карточка. Локаторы: `today.starter`, `today.study`, `session.progress`,
`tab.today` (в занятии скрыт). Выход из занятия — первая кнопка навигационной
панели.

## Proof

`session.progress` видна, `tab.today` скрыта. База в памяти — эффект виден
только на экране (карточки в занятии).

## Charters

```
study-session|ios|default|Starting on Today with an empty database, add the starter deck, study several cards with different grades and leave the session; report wrong counts, stuck cards or a tab bar that does not come back
```

## Gotchas

- Звуки, Live Activity и проверка возраста в `-ui-testing` выключены — так и задумано.
