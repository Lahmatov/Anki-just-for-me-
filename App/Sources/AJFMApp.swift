import SwiftUI
import SwiftData
import AJFMCore

@main
struct AJFMApp: App {
    init() {
        // Язык — до первой строки на экране: выбранный в настройках,
        // а пока не выбран — системный.
        Loc.language = AppSettings.language
        // До первого экрана: заголовки навигации создаются один раз
        // и потом шрифт уже не подхватывают.
        AppFont.current.applyToNavigationBars()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Folder.self, Deck.self, Note.self, Card.self, Review.self,
            RetellSession.self, UsageEntry.self, RewardContractEntity.self,
            ProgressSnapshot.self,
        ])
    }
}
