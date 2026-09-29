import XCTest
@testable import AJFMCore

final class BundledCatalogTests: XCTestCase {

    override func tearDown() {
        Loc.language = .russian
    }

    private let note = CatalogNote(
        term: "hang out", ipa: "/hæŋ ˈaʊt/", partOfSpeech: "phrasal verb",
        translation: ["ru": "тусоваться", "pt": "passar tempo", "en": "to spend time together"],
        example: "We hang out here.",
        exampleTranslation: ["ru": "Мы тут тусуемся.", "pt": "Passamos tempo aqui."],
        cloze: "We ___ here.",
        note: ["ru": "Разделяемый глагол нельзя разрывать.", "en": ""])

    private func show(_ notes: [CatalogNote], title: String = "Pilot") -> (CatalogShowFile, CatalogEpisode) {
        let episode = CatalogEpisode(season: 1, episode: 3, title: title, notes: notes)
        return (CatalogShowFile(name: "Friends", year: 1994, accent: "US", rank: 1, episodes: [episode]), episode)
    }

    // MARK: - Разбор

    func testIndexDecodes() throws {
        let json = #"{"format":"recap-catalog","version":1,"shows":[{"resource":"catalog-show-01","name":"Friends","year":1994,"accent":"US","rank":1,"episodes":24,"words":360}]}"#
        let index = try BundledCatalog.decodeIndex(Data(json.utf8))
        XCTAssertEqual(index.shows.first?.name, "Friends")
        XCTAssertEqual(index.shows.first?.words, 360)
    }

    func testForeignIndexIsRejected() {
        let json = #"{"format":"ajfm-deck","version":1,"shows":[]}"#
        XCTAssertThrowsError(try BundledCatalog.decodeIndex(Data(json.utf8))) {
            XCTAssertEqual($0 as? BundledCatalog.Failure, .foreignFormat)
        }
    }

    func testNewerIndexVersionIsRejected() {
        let json = #"{"format":"recap-catalog","version":2,"shows":[]}"#
        XCTAssertThrowsError(try BundledCatalog.decodeIndex(Data(json.utf8))) {
            XCTAssertEqual($0 as? BundledCatalog.Failure, .unsupportedVersion(2))
        }
    }

    func testBrokenJSONThrows() {
        XCTAssertThrowsError(try BundledCatalog.decodeIndex(Data("{".utf8)))
        XCTAssertThrowsError(try BundledCatalog.decodeShow(Data()))
    }

    func testShowFileRoundTrips() throws {
        let (file, _) = show([note])
        let data = try JSONEncoder().encode(file)
        XCTAssertEqual(try BundledCatalog.decodeShow(data), file)
    }

    // MARK: - Слова на языке ученика

    func testRussianNoteTakesRussianFields() {
        let notes = BundledCatalog.notes([note], language: .russian)
        XCTAssertEqual(notes.first?.translation, "тусоваться")
        XCTAssertEqual(notes.first?.exampleTranslation, "Мы тут тусуемся.")
        XCTAssertEqual(notes.first?.note, "Разделяемый глагол нельзя разрывать.")
        XCTAssertEqual(notes.first?.partOfSpeech, .phrasalVerb)
        XCTAssertEqual(notes.first?.cloze, "We ___ here.")
    }

    func testEnglishNoteHasDefinitionAndNoExampleTranslation() {
        let notes = BundledCatalog.notes([note], language: .english)
        XCTAssertEqual(notes.first?.translation, "to spend time together")
        XCTAssertNil(notes.first?.exampleTranslation)
        XCTAssertNil(notes.first?.note, "пустая заметка не превращается в пустую строку")
    }

    func testNoteWithoutTranslationForLanguageIsSkipped() {
        var partial = note
        partial.translation["pt"] = "  "
        XCTAssertTrue(BundledCatalog.notes([partial], language: .portuguese).isEmpty)
        XCTAssertEqual(BundledCatalog.notes([partial], language: .russian).count, 1)
    }

    func testKnownTermsAreSkippedIgnoringCase() {
        let notes = BundledCatalog.notes([note], language: .russian, knownTerms: ["Hang Out"])
        XCTAssertTrue(notes.isEmpty)
    }

    func testUnknownPartOfSpeechBecomesNil() {
        var odd = note
        odd.partOfSpeech = "gerund"
        XCTAssertNil(BundledCatalog.notes([odd], language: .russian).first?.partOfSpeech)
    }

    // MARK: - Набор

    func testDeckGoesToShowSeasonFolderInLearnersLanguage() {
        let (file, episode) = show([note])
        let russian = BundledCatalog.deckFile(show: file, episode: episode, language: .russian)
        XCTAssertEqual(russian.deck.name, "S01E03 · Pilot")
        XCTAssertEqual(russian.deck.folder, "Сериалы/Friends/Сезон 1")
        XCTAssertEqual(russian.deck.source, "Friends S01E03")
        let portuguese = BundledCatalog.deckFile(show: file, episode: episode, language: .portuguese)
        XCTAssertEqual(portuguese.deck.folder, "Séries/Friends/Temporada 1")
        let english = BundledCatalog.deckFile(show: file, episode: episode, language: .english)
        XCTAssertEqual(english.deck.folder, "TV shows/Friends/Season 1")
    }

    func testEpisodeWithoutTitleIsNamedByCode() {
        let (file, episode) = show([note], title: "")
        XCTAssertEqual(BundledCatalog.deckFile(show: file, episode: episode, language: .russian).deck.name,
                       "S01E03")
    }

    func testDeckFilePassesTheStrictParser() throws {
        let (file, episode) = show([note])
        let data = try JSONEncoder().encode(BundledCatalog.deckFile(show: file, episode: episode, language: .russian))
        let parsed = try DeckParser.parse(data: data)
        XCTAssertEqual(parsed.notes.map(\.term), ["hang out"])
    }
}
