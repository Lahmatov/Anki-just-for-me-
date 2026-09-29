import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

@MainActor
final class LocalCatalogTests: XCTestCase {

    private func fixture() -> (CatalogShowFile, CatalogEpisode) {
        let notes = (1...6).map { index in
            CatalogNote(term: "phrase \(index)",
                        translation: ["ru": "фраза \(index)", "pt": "frase \(index)", "en": "phrase \(index)"],
                        example: "Say phrase \(index).", cloze: "Say ___.")
        }
        let episode = CatalogEpisode(season: 1, episode: 2, title: "The One With Tests", notes: notes)
        return (CatalogShowFile(name: "Friends", year: 1994, rank: 1, episodes: [episode]), episode)
    }

    func testEpisodeBecomesDeckInShowSeasonFolder() throws {
        let context = try TestDB.makeContext()
        let (show, episode) = fixture()

        let result = try LocalCatalog.install(episode: episode, of: show, language: .russian, into: context)

        XCTAssertEqual(result.addedNotes, 6)
        let deck = try XCTUnwrap(try context.fetch(FetchDescriptor<Deck>()).first)
        XCTAssertEqual(deck.name, "S01E02 · The One With Tests")
        XCTAssertEqual(deck.source, "Friends S01E02")
        XCTAssertEqual(deck.folder?.name, "Сезон 1")
        XCTAssertEqual(deck.folder?.parent?.name, "Friends")
    }

    func testInstalledEpisodeIsRecognisedBySource() throws {
        let context = try TestDB.makeContext()
        let (show, episode) = fixture()
        XCTAssertFalse(LocalCatalog.installedSources(in: context)
            .contains(LocalCatalog.source(show: show, episode: episode)))

        try LocalCatalog.install(episode: episode, of: show, language: .russian, into: context)

        XCTAssertTrue(LocalCatalog.installedSources(in: context)
            .contains(LocalCatalog.source(show: show, episode: episode)))
    }

    func testAddingTheSameEpisodeTwiceDoesNotDuplicateWords() throws {
        let context = try TestDB.makeContext()
        let (show, episode) = fixture()
        try LocalCatalog.install(episode: episode, of: show, language: .russian, into: context)

        let second = try LocalCatalog.install(episode: episode, of: show, language: .russian, into: context)

        XCTAssertEqual(second.addedNotes, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Note>()), 6)
    }

    func testEmptyDatabaseHasNothingInstalled() throws {
        let context = try TestDB.makeContext()
        XCTAssertTrue(LocalCatalog.installedSources(in: context).isEmpty)
    }

    /// Каталог, который собран в приложение, читается целиком: каждый
    /// сериал из оглавления открывается, серии не пустые.
    func testBundledCatalogOpensEveryShow() throws {
        guard let index = LocalCatalog.index() else {
            throw XCTSkip("каталог ещё не собран в ресурсы")
        }
        XCTAssertFalse(index.shows.isEmpty)
        for entry in index.shows {
            let show = try XCTUnwrap(LocalCatalog.show(entry), entry.name)
            XCTAssertEqual(show.episodes.count, entry.episodes, entry.name)
            XCTAssertTrue(show.episodes.allSatisfy { $0.notes.count >= 5 }, entry.name)
        }
    }
}
