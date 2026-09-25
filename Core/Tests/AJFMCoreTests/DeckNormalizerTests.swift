import XCTest
@testable import AJFMCore

/// Наборы, которые языковая модель пишет «почти по формату».
/// Каждый случай — реальный вариант того, как модель путает поля.
final class DeckNormalizerTests: XCTestCase {

    private func parse(_ text: String) throws -> DeckFile {
        try DeckParser.parse(data: Data(text.utf8))
    }

    func testCardsInsteadOfNotes() throws {
        // Именно так сломался первый импорт с телефона: всё по формату,
        // кроме названия списка.
        let file = try parse("""
        { "format": "ajfm-deck", "version": 1, "deck": { "name": "Friends S01E01" },
          "cards": [ { "term": "hang out", "translation": "тусоваться" } ] }
        """)
        XCTAssertEqual(file.deck.name, "Friends S01E01")
        XCTAssertEqual(file.notes.map(\.term), ["hang out"])
    }

    func testNotesNestedInsideDeck() throws {
        let file = try parse("""
        { "deck": { "name": "X", "notes": [ { "term": "a", "translation": "б" } ] } }
        """)
        XCTAssertEqual(file.notes.count, 1)
        XCTAssertEqual(file.format, DeckFile.formatID)
    }

    func testTopLevelArrayGetsDefaultName() throws {
        let file = try parse("""
        [ { "word": "eventually", "meaning": "в конце концов" } ]
        """)
        XCTAssertEqual(file.deck.name, DeckNormalizer.fallbackDeckName)
        XCTAssertEqual(file.notes[0].term, "eventually")
        XCTAssertEqual(file.notes[0].translation, "в конце концов")
    }

    func testFieldAliasesAndCaseStyles() throws {
        let file = try parse("""
        { "title": "Mix", "words": [ {
            "Word": "pull off", "Translation": "провернуть",
            "part_of_speech": "Phrasal_Verb", "IPA": "/pʊl ɔf/",
            "example_sentence": "We pulled it off.",
            "example_translation": "Мы это провернули.",
            "synonyms": "manage, succeed"
        } ] }
        """)
        let note = try XCTUnwrap(file.notes.first)
        XCTAssertEqual(file.deck.name, "Mix")
        XCTAssertEqual(note.term, "pull off")
        XCTAssertEqual(note.partOfSpeech, .phrasalVerb)
        XCTAssertEqual(note.ipa, "/pʊl ɔf/")
        XCTAssertEqual(note.example, "We pulled it off.")
        XCTAssertEqual(note.exampleTranslation, "Мы это провернули.")
        XCTAssertEqual(note.synonyms, ["manage", "succeed"])
    }

    func testFrontBackFlashcardStyle() throws {
        let file = try parse("""
        { "name": "Cards", "flashcards": [ { "front": "leverage", "back": "рычаг" } ] }
        """)
        XCTAssertEqual(file.notes[0].term, "leverage")
        XCTAssertEqual(file.notes[0].translation, "рычаг")
    }

    func testTranslationListIsJoined() throws {
        let file = try parse("""
        { "name": "X", "notes": [ { "term": "run", "translations": ["бежать", "управлять"] } ] }
        """)
        XCTAssertEqual(file.notes[0].translation, "бежать, управлять")
    }

    func testFirstOfSeveralExamplesIsKept() throws {
        let file = try parse("""
        { "name": "X", "notes": [ { "term": "run", "translation": "бежать",
          "examples": ["Run!", "He runs a shop."] } ] }
        """)
        XCTAssertEqual(file.notes[0].example, "Run!")
    }

    func testMarkdownFenceAndChatter() throws {
        let file = try parse("""
        Конечно! Вот набор по серии:

        ```json
        { "format": "ajfm-deck", "version": 1, "deck": { "name": "Fenced" },
          "notes": [ { "term": "cliffhanger", "translation": "обрыв на самом интересном" } ] }
        ```

        Удачи в изучении!
        """)
        XCTAssertEqual(file.deck.name, "Fenced")
    }

    func testByteOrderMarkIsIgnored() throws {
        let file = try parse("\u{FEFF}" + """
        { "name": "BOM", "notes": [ { "term": "a", "translation": "б" } ] }
        """)
        XCTAssertEqual(file.deck.name, "BOM")
    }

    func testPlainLinesBecomeNotes() throws {
        let file = try parse("""
        { "name": "Lines", "words": ["leverage — рычаг", "turn out - оказаться"] }
        """)
        XCTAssertEqual(file.notes.map(\.term), ["leverage", "turn out"])
        XCTAssertEqual(file.notes.map(\.translation), ["рычаг", "оказаться"])
    }

    func testSingleKeyWrapper() throws {
        let file = try parse("""
        { "result": { "name": "Wrapped", "cards": [ { "term": "a", "translation": "б" } ] } }
        """)
        XCTAssertEqual(file.deck.name, "Wrapped")
    }

    func testCanonicalFileIsUntouched() throws {
        let original = DeckFile(
            deck: DeckMeta(name: "Same", folder: "A/B", scheduler: .leitner,
                           cardTypes: [.spelling], source: "S01E01"),
            notes: [NoteData(term: "run", translation: "бежать", ipa: "/rʌn/",
                             partOfSpeech: .verb, example: "Run!", tags: ["t"],
                             difficulty: .easy)])
        XCTAssertEqual(try DeckParser.parse(data: try DeckParser.encode(original)), original)
    }

    // MARK: - Что по-прежнему отвергается

    func testNoListOfWordsIsStillAnError() {
        XCTAssertThrowsError(try parse(#"{ "name": "Empty", "comment": "nothing" }"#)) {
            XCTAssertEqual($0 as? DeckParseError, .noNotes)
        }
    }

    func testMissingTranslationNamesTheWord() {
        XCTAssertThrowsError(try parse("""
        { "name": "X", "cards": [ { "term": "ok", "translation": "ок" }, { "word": "lonely" } ] }
        """)) {
            XCTAssertEqual($0 as? DeckParseError, .missingField(noteIndex: 1, field: "translation"))
        }
    }

    func testForeignFormatIsStillRejected() {
        XCTAssertThrowsError(try parse("""
        { "format": "anki-apkg", "notes": [ { "term": "a", "translation": "б" } ] }
        """)) {
            XCTAssertEqual($0 as? DeckParseError, .wrongFormat(found: "anki-apkg"))
        }
    }

    func testProseWithoutJSON() {
        XCTAssertThrowsError(try parse("Извини, я не могу сделать набор.")) {
            guard case .notJSON = $0 as? DeckParseError else {
                return XCTFail("ожидалась ошибка «не JSON», получено \($0)")
            }
        }
    }

    func testBrokenJSONInsideFence() {
        XCTAssertThrowsError(try parse("```json\n{ \"name\": \"X\", \"notes\": [ \n```"))
    }

    func testNonObjectItemsBecomeEmptyAndAreReported() {
        XCTAssertThrowsError(try parse(#"{ "name": "X", "notes": [42] }"#)) {
            XCTAssertEqual($0 as? DeckParseError, .missingField(noteIndex: 0, field: "term"))
        }
    }
}
