import SwiftUI
import SwiftData
import AJFMCore

@main
struct AJFMApp: App {
    private let container: ModelContainer

    init() {
        UITesting.prepare()
        // Язык — до первой строки на экране: выбранный в настройках,
        // а пока не выбран — системный.
        Loc.language = AppSettings.language
        // До первого экрана: заголовки навигации создаются один раз
        // и потом шрифт уже не подхватывают.
        AppFont.current.applyToNavigationBars()

        let schema = Schema([
            Folder.self, Deck.self, Note.self, Card.self, Review.self,
            RetellSession.self, UsageEntry.self, RewardContractEntity.self,
            ProgressSnapshot.self, TrackedShow.self,
        ])
        // В UI-тестах база в памяти: каждый прогон — как первая установка.
        let configuration = ModelConfiguration(schema: schema,
                                               isStoredInMemoryOnly: UITesting.isActive)
        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // Без базы приложению делать нечего; так же вёл себя и
            // `.modelContainer(for:)`, только молча.
            fatalError("Model container failed to open: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
