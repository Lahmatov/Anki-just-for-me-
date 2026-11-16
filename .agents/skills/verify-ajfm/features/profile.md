# Документы в профиле

## Sub-features

- Настройки → Профиль: аватар (`profile.avatar`), ключи AI (`profile.aikeys`),
  помощь (`profile.help`).
- Условия, политика и лицензии (`docs.terms`, `docs.privacy`, `docs.licenses`) —
  файлы из `docs/legal`, без сети.

## How to get to it (user POV)

Вкладка «Настройки» (`tab.settings`) → «Профиль» (`settings.profile`) → прокрутить
вниз → «Terms of Use».

## Driving it with e2e

`tests/ios/profile.e2e.ts` — точный путь со `screen.scrollUntilVisible`
(список ленивый: строки ниже экрана нет в дереве); `tests/ios/agent.e2e.ts`
(«finds the Terms of Use from the Today screen») — `agent.act` с «Сегодня».

## Proof

Виден заголовок `Recap — Terms of Use` (на английском, по аргументам запуска).

## Charters

```
profile-docs|ios|default|Starting on the Profile screen, open each legal document and come back; report a document that is missing, untranslated or cut off
```

## Gotchas

- Имя продавца и почта в документах — заглушки `CHANGE-ME` до выпуска: не ошибка.
