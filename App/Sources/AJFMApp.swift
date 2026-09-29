import SwiftUI
import SwiftData
import AJFMCore

@main
struct AJFMApp: App {
    private let container: ModelContainer

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
        if UITesting.wantsDemoData {
            _ = StarterDeck.install(into: container.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
