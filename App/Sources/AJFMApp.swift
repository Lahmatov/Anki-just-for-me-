import SwiftUI
import SwiftData
import AJFMCore

@main
struct AJFMApp: App {
    @State private var languages = StudyLanguageStore.shared

    init() {
        UITesting.prepare()
        // Постеры сериалов (AsyncImage) кешируются на диске: без этого
        // каждый показ списка заново качал и декодировал картинки — лишняя
        // работа сети и процессора, а значит, и тепло.
        URLCache.shared = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
        // Язык — до первой строки на экране: выбранный в настройках,
        // а пока не выбран — системный.
        Loc.language = AppSettings.language
        // До первого экрана: заголовки навигации создаются один раз
        // и потом шрифт уже не подхватывают.
        AppFont.current.applyToNavigationBars()

        // Сбои от iOS и первый запуск для просьбы об оценке (P-74).
        DiagnosticsService.shared.start()
        ReviewPromptService.noteLaunch()

        // База открывается для изучаемого языка; у каждого языка своя (P-67).
        let container = StudyLanguageStore.shared.currentContainer
        if UITesting.wantsDemoData {
            _ = StarterDeck.install(into: container.mainContext)
        }
        if UITesting.wantsDemoShow {
            UITesting.installDemoShow(into: container.mainContext)
        }
        if UITesting.wantsDemoLesson {
            UITesting.installDemoLesson(into: container.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            // Смена изучаемого языка — другая база и другие ключи прогресса:
            // экраны пересоздаются целиком, ничего старого в них не остаётся.
            RootView()
                .modelContainer(languages.currentContainer)
                .id(languages.current)
        }
    }
}
