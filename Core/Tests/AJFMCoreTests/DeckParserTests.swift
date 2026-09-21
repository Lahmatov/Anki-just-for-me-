import XCTest
@testable import AJFMCore

final class TermNormalizerTests: XCTestCase {
    func testCaseAndWhitespace() {
        XCTAssertEqual(TermNormalizer.normalize("  Pull   Off  "), "pull off")
    }

    func testStripsInfinitiveAndArticles() {
        XCTAssertEqual(TermNormalizer.normalize("to pull off"), "pull off")
        XCTAssertEqual(TermNormalizer.normalize("The leverage"), "leverage")
        XCTAssertEqual(TermNormalizer.normalize("an apple"), "apple")
    }

    func testKeepsShortWordsIntact() {
        // «to» и «a» — сами по себе слова, не префиксы.
        XCTAssertEqual(TermNormalizer.normalize("to"), "to")
        XCTAssertEqual(TermNormalizer.normalize("a"), "a")
    }

    func testStripsTrailingPunctuation() {
        XCTAssertEqual(TermNormalizer.normalize("pull off."), "pull off")
        XCTAssertEqual(TermNormalizer.normalize("really?!"), "really")
    }

    func testTermsThatShouldCollide() {
        XCTAssertEqual(
            TermNormalizer.normalize("To Pull Off"),
            TermNormalizer.normalize("pull off")
        )
    }
}

final class DeckParserTests: XCTestCase {
    private func json(_ s: String) -> Data { s.data(using: .utf8)! }

    private let minimal = """
    {
      "format": "ajfm-deck",
      "version": 1,
      "deck": { "name": "Test" },
      "notes": [ { "term": "leverage", "translation": "рычаг" } ]
    }
    """

    func testParsesMinimalFile() throws {
        let file = try DeckParser.parse(data: json(minimal))
        XCTAssertEqual(file.deck.name, "Test")
        XCTAssertEqual(file.notes.count, 1)
        XCTAssertEqual(file.notes[0].term, "leverage")
        XCTAssertNil(file.deck.scheduler)
    }

    func testParsesFullFile() throws {
        let data = json("""
        {
          "format": "ajfm-deck",
          "version": 1,
          "deck": {
            "name": "Breaking Bad S03E05",
            "folder": "Сериалы/Breaking Bad",
            "scheduler": "fsrs6",
            "cardTypes": ["recognition", "pronunciation"]
          },
          "notes": [{
            "term": "to pull off",
            "translation": "провернуть",
            "partOfSpeech": "phrasal verb",
            "difficulty": "medium",
            "synonyms": ["manage"],
            "tags": ["phrasal"]
          }]
        }
        """)
        let file = try DeckParser.parse(data: data)
        XCTAssertEqual(file.deck.scheduler, .fsrs6)
        XCTAssertEqual(file.deck.cardTypes, [.recognition, .pronunciation])
        XCTAssertEqual(file.notes[0].partOfSpeech, .phrasalVerb)
        XCTAssertEqual(file.notes[0].difficulty, .medium)
    }

    func testRejectsForeignFormat() {
        let data = json("""
        { "format": "anki-apkg", "version": 1, "deck": { "name": "X" },
          "notes": [{ "term": "a", "translation": "б" }] }
        """)
        XCTAssertThrowsError(try DeckParser.parse(data: data)) { error in
            XCTAssertEqual(error as? DeckParseError, .wrongFormat(found: "anki-apkg"))
        }
    }

    func testRejectsNewerVersion() {
        let data = json("""
        { "format": "ajfm-deck", "version": 99, "deck": { "name": "X" },
          "notes": [{ "term": "a", "translation": "б" }] }
        """)
        XCTAssertThrowsError(try DeckParser.parse(data: data)) { error in
            XCTAssertEqual(
                error as? DeckParseError,
                .unsupportedVersion(found: 99, supported: DeckFile.supportedVersion))
        }
    }

    func testRejectsEmptyNotes() {
        let data = json("""
        { "format": "ajfm-deck", "version": 1, "deck": { "name": "X" }, "notes": [] }
        """)
        XCTAssertThrowsError(try DeckParser.parse(data: data)) { error in
            XCTAssertEqual(error as? DeckParseError, .noNotes)
        }
    }

    func testRejectsBlankTranslation() {
        let data = json("""
        { "format": "ajfm-deck", "version": 1, "deck": { "name": "X" },
          "notes": [{ "term": "word", "translation": "   " }] }
        """)
        XCTAssertThrowsError(try DeckParser.parse(data: data)) { error in
            XCTAssertEqual(error as? DeckParseError, .missingField(noteIndex: 0, field: "translation"))
        }
    }

    func testUnknownEnumValuesDoNotBreakImport() throws {
        // Опечатка в необязательном поле не должна ронять весь набор.
        let data = json("""
        { "format": "ajfm-deck", "version": 1,
          "deck": { "name": "X", "scheduler": "supermemo-17", "cardTypes": ["recognition", "telepathy"] },
          "notes": [{ "term": "word", "translation": "слово", "partOfSpeech": "gerundish" }] }
        """)
        let file = try DeckParser.parse(data: data)
        XCTAssertNil(file.deck.scheduler)
        XCTAssertEqual(file.deck.cardTypes, [.recognition])
        XCTAssertNil(file.notes[0].partOfSpeech)
    }

    func testNotJSON() {
        XCTAssertThrowsError(try DeckParser.parse(string: "конечно, вот твой набор: ..."))
    }

    func testRoundTrip() throws {
        let original = DeckFile(
            deck: DeckMeta(name: "Test", folder: "A/B", scheduler: .sm2, cardTypes: [.listening]),
            notes: [NoteData(term: "run", translation: "бежать", partOfSpeech: .verb)]
        )
        let decoded = try DeckParser.parse(data: try DeckParser.encode(original))
        XCTAssertEqual(decoded, original)
    }
}
