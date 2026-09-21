import Foundation
import SwiftData
import AJFMCore
@testable import AJFM

/// База в памяти: между тестами ничего не остаётся на диске.
@MainActor
enum TestDB {
    static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Folder.self, Deck.self, Note.self, Card.self, Review.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    static func deckFile(
        name: String = "Набор",
        folder: String? = nil,
        scheduler: SchedulerID? = nil,
        cardTypes: [CardType]? = nil,
        notes: [NoteData]
    ) -> Data {
        let file = DeckFile(
            deck: DeckMeta(
                name: name, folder: folder, scheduler: scheduler, cardTypes: cardTypes),
            notes: notes
        )
        return try! DeckParser.encode(file)
    }
}
