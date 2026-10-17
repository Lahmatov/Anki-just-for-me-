---
name: ios-architecture
description: Архитектура iOS-приложения Recap — MVVM на @Observable, навигация NavigationStack + NavigationPath, превью с mock-данными, где класть логику и тесты. Использовать при создании или изменении любого экрана, модели представления, навигации или превью в App/, а также при ревью такого кода.
---

# Архитектура Recap: MVVM, навигация, превью

Правила владельца проекта. Они важнее советов из `swiftui-review` и `ios-polish`,
если те им противоречат.

## Версия iOS

- Цель проекта — `deploymentTarget` в `project.yml` (сейчас **iOS 26**: Liquid Glass,
  Declared Age Range, `safeAreaBar`). Цель не меняется без решения владельца.
- Базовое правило владельца — «минимум iOS 17»: **новый код не должен требовать
  больше, чем нужно**. API новее iOS 17 — только если без него нельзя, и тогда
  в пределах цели проекта (iOS 26) или под `if #available`.
- `Core/` — без SwiftUI, SwiftData и UIKit (Foundation + свои типы), поэтому он
  переносим на любую версию и тестируется `swift test` без симулятора.

## Слои

| Слой | Где | Что в нём | Тесты |
|---|---|---|---|
| Логика и форматы | `Core/Sources/AJFMCore/` | алгоритмы, разбор, формулы прогресса, правила (`ReviewPrompt`, `AgeAssurance`, `RegionPolicy`) | `Core/Tests` — обязательно |
| Сервисы | `App/Sources/Services/` | SwiftData, сеть, Keychain, системные фреймворки | `App/Tests` (база в памяти) |
| ViewModel | `App/Sources/ViewModels/` | состояние экрана и действия пользователя | `App/Tests` |
| View | `App/Sources/Views/` | только раскладка и привязки | превью + UI-тесты |

Логика по умолчанию — в `Core/`. В ViewModel остаётся склейка: позвать сервис,
положить результат в состояние, показать ошибку.

## Правило 1. Состояние — только `@Observable`

```swift
import Observation

@Observable
@MainActor
final class LessonHubViewModel {
    private(set) var lessons: [LessonSummary] = []
    private(set) var error: String?
    var query = ""

    private let library: LessonLibrary

    init(library: LessonLibrary) {
        self.library = library
    }

    func load() async { ... }
    func delete(_ lesson: LessonSummary) { ... }
}
```

- Никогда: `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`,
  `@EnvironmentObject`.
- Класс с `@Observable` всегда с `@MainActor` (в проекте нет MainActor по умолчанию).
- Владеет моделью экран: `@State private var model = LessonHubViewModel(...)`.
  Передаётся дальше через `@Bindable` (нужны привязки) или обычным параметром.
  Общие на всё приложение (`RecapAccount.shared`, `StudyLanguageStore`) — через
  `@Environment(Type.self)` или синглтон, как уже заведено.
- `@AppStorage` внутри `@Observable` не работает — настройки читает View
  или `AppSettings`.
- Модели, которым нужен `ModelContext`, создаются в `.task {}` экрана
  (контекст из `@Environment(\.modelContext)` в `init` ещё недоступен) —
  как `ReviewSessionViewModel` в `ReviewSessionView`.

## Правило 2. Навигация — `NavigationStack` + `NavigationPath`

Устроено в `App/Sources/Navigation/`:

- `AppRoute` — все экраны, куда переходят внутри стека. В значениях только
  `Hashable`-данные: `PersistentIdentifier` записи, `EpisodeContext`, строки.
  Ни записей SwiftData, ни замыканий.
- `AppRouteView` — экран по маршруту; запись достаёт по идентификатору
  из базы текущего языка, удалённая — экран «уже удалено».
- `Router` (`@Observable @MainActor`) — `NavigationPath` одного стека,
  `push(_:)`, `popToRoot()`. Лежит в окружении: `@Environment(Router.self)`.
- `.routedStack(router)` — корень стека: `NavigationStack(path:)`, все
  `AppRoute` и роутер в окружении. `RoutedStack { … }` — то же со своим
  роутером для листов и превью.

```swift
// Переход по нажатию
NavigationLink(value: AppRoute.deck(deck.persistentModelID)) { DeckRow(deck: deck) }
CardLink(title: "…", systemImage: "chart.bar.fill", route: .stats)

// Переход из кода
@Environment(Router.self) private var router
router.push(.review(deck: deck.persistentModelID))

// Корень вкладки, которому самому нужно переходить
@State private var router = Router()
var body: some View { content.routedStack(router) }

// Лист со своим стеком
.sheet(isPresented: $showPlus) { RoutedStack { PlusView() } }
```

- Никогда: `NavigationView`, `NavigationLink(destination:)`,
  `NavigationLink { экран } label: { … }`, голый `NavigationStack` без пути.
- Экрану нужно замыкание или привязка (сообщить «шаг пройден», выбрать
  провайдера) — свой маленький `Hashable`-маршрут и `navigationDestination(for:)`
  в том экране, который их держит: `RecapStep` в `EpisodeRecapView`,
  `AIProvider` в `AIKeysView`, `SettingsView.Route`. В `AppRoute` замыкание
  не положить.
- `navigationDestination(for:)` — один раз на тип в одном стеке.
- Путь — в `@State` корня вкладки: вкладки навигируют независимо.
- Новый экран: case в `AppRoute`, строка в `AppRouteView`, превью.

## Правило 3. View — раскладка, ViewModel — логика

В View можно: раскладку, привязки, анимации, доступность, вызов метода модели.
В View нельзя: запросы к базе кроме `@Query`, сеть, разбор данных, расчёты
прогресса, ветвистую логику в `Button { … }`, `.task {}`, `.onAppear {}`.

- Действие кнопки — метод: `Button("Удалить", action: model.delete)`.
- Длинный `body` (больше ~80 строк) делится на отдельные `struct …: View`
  в своих файлах, а не на `var section: some View`.
- Числа, проценты, даты — `FormatStyle` (`Text(value, format: .percent)`),
  а не `String(format:)`.
- Тексты интерфейса — `tr("ру", "pt", "en")`: так устроена локализация проекта
  (кириллица вне `tr()` ловится `tools/lint.py`).

## Правило 4. У каждого экрана — превью с mock-данными

Каждый файл с `View` заканчивается блоком превью. Данные — из `PreviewData`
(`App/Sources/Preview/`): база SwiftData в памяти с готовым набором, уроком,
сериалом и историей повторений.

```swift
#if DEBUG
private struct Previews: View {
    @State private var text = "hang out"

    var body: some View {
        QuickAddView(initialText: text)
            .previewEnvironment()
    }
}

#Preview("Светлая") { Previews() }
#Preview("Тёмная") { Previews().preferredColorScheme(.dark) }
#endif
```

- `struct Previews: View` — `private`, по одному на файл; держит `@State`
  для привязок и собирает mock-данные. Сам показ — макрос `#Preview`,
  не `PreviewProvider`.
- `.previewEnvironment()` даёт контейнер в памяти, язык, тему и синглтоны —
  без него экраны с `@Query` в Canvas падают.
- Минимум два состояния: обычное и крайнее (пусто, ошибка, длинный текст,
  крупный шрифт `.dynamicTypeSize(.accessibility3)`).
- Превью не ходят в сеть: сервисы с сетью получают заглушки из `PreviewData`.
- Всё превью — под `#if DEBUG`: mock-данные не попадают в выпуск.

## Тесты

- Новая логика ViewModel — тест в `App/Tests` на `ModelConfiguration(isStoredInMemoryOnly: true)`
  (`TestDB.makeContext()`); логика без SwiftData — в `Core/Tests`.
- Перед коммитом — `python3 tools/lint.py` (см. навык `ios-verify`).

## Чек-лист нового экрана

1. Логика — в `Core/` (с тестом) или в `…ViewModel` (`@Observable @MainActor`).
2. View без логики; действия — методы модели.
3. Переходы — case в `AppRoute` + `NavigationLink(value:)` или `router.push`.
4. Тексты — `tr()`, числа — `FormatStyle`.
5. Превью: `private struct Previews: View` + `#Preview`, два состояния.
6. `accessibilityIdentifier` на том, что трогают UI-тесты.
7. Lint, затем CI (навык `ios-verify`).
