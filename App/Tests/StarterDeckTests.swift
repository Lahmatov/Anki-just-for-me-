import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

@MainActor
final class StarterDeckTests: XCTestCase {

    func testBundledDeckExistsAndParses() throws {
        // Стартовый набор лежит в ресурсах приложения. Если он потеряется
        // при сборке, первый запуск встретит пустым экраном — ровно тем,
        // ради чего набор и добавлен.
        let data = try XCTUnwrap(
            StarterDeck.data(), "starter-deck.json не попал в ресурсы приложения")
        let file = try DeckParser.parse(data: data)

        XCTAssertEqual(file.format, DeckFile.formatID)
        XCTAssertGreaterThanOrEqual(file.notes.count, 10)
        XCTAssertEqual(StarterDeck.wordCount(), file.notes.count)
    }

    func testEveryStarterWordHasContext() throws {
        let file = try DeckParser.parse(data: try XCTUnwrap(StarterDeck.data()))
        for note in file.notes {
            XCTAssertFalse(note.translation.isEmpty, "\(note.term): нет перевода")
            XCTAssertNotNil(note.example, "\(note.term): нет примера")
            XCTAssertNotNil(note.ipa, "\(note.term): нет транскрипции")
        }
    }

    func testInstallFillsEmptyDatabase() throws {
        let context = try TestDB.makeContext()
        let result = try XCTUnwrap(StarterDeck.install(into: context))

        XCTAssertGreaterThan(result.addedNotes, 0)
        XCTAssertGreaterThan(result.addedCards, result.addedNotes, "карточек больше, чем слов")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Deck>()).count, 1)
    }

    func testInstallingTwiceAddsNothingNew() throws {
        let context = try TestDB.makeContext()
        StarterDeck.install(into: context)
        let second = try XCTUnwrap(StarterDeck.install(into: context))

        // Повторное знакомство не должно плодить дубли.
        XCTAssertEqual(second.addedNotes, 0)
        XCTAssertGreaterThan(second.skippedDuplicates, 0)
    }

    func testStarterDeckIsImmediatelyLearnable() throws {
        let context = try TestDB.makeContext()
        StarterDeck.install(into: context)

        // Смысл набора в том, чтобы сразу было что учить.
        let queue = try ReviewService(context: context).todayQueue()
        XCTAssertFalse(queue.isEmpty)
        XCTAssertGreaterThan(queue.summary.new, 0)
    }
}
