import SwiftUI
import SwiftData

@main
struct AJFMApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Folder.self, Deck.self, Note.self, Card.self, Review.self])
    }
}
