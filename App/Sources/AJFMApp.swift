import SwiftUI
import SwiftData

@main
struct AJFMApp: App {
    init() {
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
