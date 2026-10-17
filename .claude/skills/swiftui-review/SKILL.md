---
name: swiftui-review
description: Ревью и написание SwiftUI-кода Recap по современным правилам — устаревшие API, разбиение View, поток данных, навигация, доступность, iPad и складной iPhone Duo, производительность, Swift Concurrency. Использовать при чтении, написании или ревью любого Swift/SwiftUI-кода в App/, Widget/, Shared/.
---

# Ревью SwiftUI-кода

Основа — [SwiftUI Pro](https://github.com/twostraws/swiftui-agent-skill) Пола
Хадсона (MIT, `references/LICENSE`). Справочники в `references/` — оригинал
без изменений; ниже — порядок работы и **поправки под этот проект**, которые
важнее справочников.

Сообщай только настоящие проблемы, не придумывай. Во время задачи — делай
задачу, а несвязанную модернизацию предлагай отдельно.

## Порядок ревью

1. Устаревшие API — `references/api.md`.
2. Разбиение View, анимации — `references/views.md`.
3. Поток данных, `@Observable`, привязки, SwiftData — `references/data.md`.
4. Навигация, листы, алерты — `references/navigation.md`.
5. HIG и единый дизайн — `references/design.md`.
6. Изменение размера окна: iPad, iPhone Duo — `references/resizability.md`.
7. Доступность — `references/accessibility.md`.
8. Локализация — `references/localization.md` (с поправкой ниже).
9. Производительность — `references/performance.md`
   (`performance-plus.md` — только для глубокого разбора по просьбе).
10. Swift и конкурентность — `references/swift.md`.
11. Гигиена — `references/hygiene.md`.

Частичное ревью — открывай только нужные справочники.

## Поправки под Recap

- **Архитектура** — навык `ios-architecture` важнее всего ниже: MVVM на
  `@Observable @MainActor`, `NavigationStack` + `NavigationPath`, View без логики,
  `private struct Previews: View` + `#Preview` с mock-данными в каждом файле.
- **Версии.** Цель — iOS 26 (`project.yml`), Swift 5 language mode, в CI Xcode 26.6
  (Duo — Xcode 27 на отдельной машине). Советы для iOS 27/27.1 и Xcode 27
  (`@ContentBuilder`, `ToolbarOverflowMenu`, `reorderable()`, `ArrangementView`,
  `toolbarVerticalEdge`) — только под `if #available` и только по просьбе;
  `@ViewBuilder` не трогать.
- **Локализация** — не String Catalog, а `tr("ру", "pt", "en")` из Core
  (`Localization`). Новый текст — сразу на трёх языках. Совет про
  `LocalizedStringResource` и `Text("…")` с ключом к проекту не относится.
- **Дизайн-константы** уже есть: `Design`, `Theme`, `.app()` шрифты, `Motion`,
  `.chunky` кнопки, `readableColumn`. Не заводить параллельные.
- **Шрифты.** Свой шрифт через `.font(.app(.body))` масштабируется с Dynamic Type —
  это не «жёсткий размер».
- **Свои вкладки.** `AppTabBar` вместо `TabView` — осознанное решение (P-28, P-49):
  живёт только открытая вкладка. Совет «перейти на TabView» — не находка,
  но на iPhone Duo проверять, что панель не перекрыта.
- **Haptics.** `Haptics.*` — общий помощник на `UIFeedbackGenerator`; новый код —
  `.sensoryFeedback(_:trigger:)`, старый переводить по ходу.
- **Один тип — один файл**: в проекте маленькие помощники живут рядом с экраном.
  Нарушение — только если файл длиннее ~400 строк или типы не связаны.
- **Тесты** — по `CLAUDE.md`: логика без Apple-фреймворков — `Core/Tests`.

## Формат ответа

По файлам. Для каждой находки:

1. Файл и строки.
2. Какое правило нарушено (например, «`clipShape(.rect(cornerRadius:))` вместо `cornerRadius()`»).
3. Короткая правка «было → стало».

Файлы без находок пропускай. В конце — приоритетный список: что исправить первым.
Большой разбор — файлом в `docs/` (как `docs/code-review.md`), а не в чате.
