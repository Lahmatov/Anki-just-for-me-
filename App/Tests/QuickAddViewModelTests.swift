import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

@MainActor
final class QuickAddViewModelTests: XCTestCase {
    private func filled(_ term: String = "hang out", _ translation: String = "тусоваться") -> QuickAddViewModel {
        let model = QuickAddViewModel()
        model.term = term
        model.translation = translation
        return model
    }

    func testCannotSaveWithoutTranslation() {
        XCTAssertFalse(filled("hang out", "  ").canSave)
    }

    func testCannotSaveWhitespaceTerm() {
        XCTAssertFalse(filled("   ", "тусоваться").canSave)
    }

    func testSaveCreatesDeckNoteAndCardsOfEachType() throws {
        let context = try TestDB.makeContext()
        let model = filled()
        XCTAssertTrue(model.save(in: context, decks: []))

        let decks = try context.fetch(FetchDescriptor<Deck>())
        XCTAssertEqual(decks.map(\.name), [QuickAddViewModel.defaultDeckName])
        let note = try XCTUnwrap(try context.fetch(FetchDescriptor<Note>()).first)
        XCTAssertEqual(note.term, "hang out")
        XCTAssertEqual(Set(note.cards.map(\.type)), Set(ImportPlanner.defaultCardTypes))
    }

    func testClozeCardIsSkippedWithoutExample() throws {
        let context = try TestDB.makeContext()
        let deck = Deck(name: "Friends", scheduler: .fsrs6, cardTypes: [.recall, .cloze])
        context.insert(deck)
        let model = filled()
        model.selectedDeckID = deck.persistentModelID
        XCTAssertTrue(model.save(in: context, decks: [deck]))
        XCTAssertEqual(deck.notes.first?.cards.map(\.type), [.recall])
    }

    func testSaveGoesToSelectedDeck() throws {
        let context = try TestDB.makeContext()
        let deck = Deck(name: "Friends", scheduler: .fsrs6, cardTypes: [.recall])
        context.insert(deck)
        let model = filled()
        model.preselect(from: [deck])
        model.save(in: context, decks: [deck])
        XCTAssertEqual(deck.notes.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Deck>()).count, 1, "новый набор не создан")
    }

    func testDuplicateIsReportedWithDeckName() throws {
        let context = try TestDB.makeContext()
        filled("Hang out", "тусоваться").save(in: context, decks: [])
        let model = filled(" hang OUT ", "")
        model.checkDuplicate(in: context)
        XCTAssertNotNil(model.duplicateWarning)
        XCTAssertTrue(model.duplicateWarning?.contains(QuickAddViewModel.defaultDeckName) ?? false)
    }

    func testEmptyTermClearsDuplicateWarning() throws {
        let context = try TestDB.makeContext()
        filled().save(in: context, decks: [])
        let model = filled()
        model.checkDuplicate(in: context)
        model.term = ""
        model.checkDuplicate(in: context)
        XCTAssertNil(model.duplicateWarning)
    }
}
