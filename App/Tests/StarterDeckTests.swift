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
            StarterDeck.data(), "starter-deck-ru.json не попал в ресурсы приложения")
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

    // MARK: - Языки

    func testEveryLanguageHasTheSameWords() throws {
        let reference = try DeckParser.parse(
            data: try XCTUnwrap(StarterDeck.data(for: .russian))).notes.map(\.term)
        for language in AppLanguage.allCases {
            let data = try XCTUnwrap(
                StarterDeck.data(for: language), "нет стартового набора для \(language)")
            let file = try DeckParser.parse(data: data)
            XCTAssertEqual(file.notes.map(\.term), reference, "\(language)")
            for note in file.notes {
                XCTAssertFalse(note.translation.isEmpty, "\(language), \(note.term)")
            }
        }
    }

    func testTranslationsAreActuallyTranslated() throws {
        // Файл-копия с русскими переводами под чужим именем — худшая ошибка
        // локализации: всё «работает», а учить по нему нельзя.
        let russian = try DeckParser.parse(data: try XCTUnwrap(StarterDeck.data(for: .russian)))
        for language in [AppLanguage.portuguese, .english] {
            let other = try DeckParser.parse(data: try XCTUnwrap(StarterDeck.data(for: language)))
            XCTAssertNotEqual(other.deck.name, russian.deck.name, "\(language)")
            XCTAssertNotEqual(
                other.notes.map(\.translation), russian.notes.map(\.translation), "\(language)")
        }
    }

    func testInstallUsesTheInterfaceLanguage() throws {
        defer { Loc.language = .russian }
        Loc.language = .portuguese
        let context = try TestDB.makeContext()
        StarterDeck.install(into: context)

        let deck = try XCTUnwrap(try context.fetch(FetchDescriptor<Deck>()).first)
        XCTAssertEqual(deck.name, "Vocabulário para recontar")
    }
}
