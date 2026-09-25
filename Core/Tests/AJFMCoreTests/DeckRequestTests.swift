import XCTest
@testable import AJFMCore

final class DeckRequestTests: XCTestCase {

    private func request(
        topic: String = "Friends S01E03", subtitles: String? = nil, count: Int = 20,
        level: CEFRLevel? = .b1, language: AppLanguage = .russian, known: [String] = []
    ) -> DeckRequest {
        DeckRequest(
            topic: topic, subtitles: subtitles, wordCount: count, level: level,
            language: language, knownTerms: known)
    }

    // MARK: - Проверка до отправки

    func testEmptyTopicWithoutSubtitlesIsRejected() {
        XCTAssertThrowsError(try request(topic: "   ").validate()) {
            XCTAssertEqual($0 as? DeckRequestError, .emptyTopic)
        }
    }

    func testSubtitlesAloneAreEnough() {
        XCTAssertNoThrow(try request(topic: "", subtitles: "Hi. How you doin'?").validate())
    }

    func testHugeSubtitlesAreRejectedBeforePaying() {
        let season = String(repeating: "a", count: DeckRequest.subtitlesLimit + 1)
        XCTAssertThrowsError(try request(subtitles: season).validate()) {
            guard case .subtitlesTooLong = $0 as? DeckRequestError else {
                return XCTFail("ожидался отказ по длине, получено \($0)")
            }
        }
    }

    // MARK: - Текст запроса

    func testWordCountIsClamped() {
        XCTAssertTrue(request(count: 500).userMessage.contains("Make a deck of 40 entries."))
        XCTAssertTrue(request(count: 0).userMessage.contains("Make a deck of 5 entries."))
    }

    func testTranslationLanguageFollowsTheApp() {
        XCTAssertTrue(request(language: .russian).system.contains("in Russian"))
        XCTAssertTrue(request(language: .portuguese).system.contains("European Portuguese"))
        XCTAssertTrue(request(language: .english).system.contains("plain-English definition"))
    }

    func testLevelAimsOneStepAbove() {
        let system = request(level: .b1).system
        XCTAssertTrue(system.contains("about B1"))
        XCTAssertTrue(system.contains("around B2"))
    }

    func testUnknownLevelFallsBackToIntermediate() {
        XCTAssertTrue(request(level: nil).system.contains("intermediate"))
    }

    func testWithoutSubtitlesExamplesMustNotPretendToBeQuotes() {
        // Главный риск функции: выдуманные «цитаты» из серии.
        let system = request(subtitles: nil).system
        XCTAssertTrue(system.contains("do not claim it is a quote"))
        XCTAssertFalse(request(subtitles: nil).userMessage.contains("<subtitles>"))
    }

    func testWithSubtitlesExamplesComeFromThem() {
        let withSubs = request(subtitles: "Joey: How you doin'?")
        XCTAssertTrue(withSubs.system.contains("exact line from the attached subtitles"))
        XCTAssertTrue(withSubs.userMessage.contains("<subtitles>\nJoey: How you doin'?\n</subtitles>"))
    }

    func testBlankSubtitlesCountAsNone() {
        XCTAssertFalse(request(subtitles: "  \n ").userMessage.contains("<subtitles>"))
    }

    func testKnownTermsAreListedButCapped() {
        let known = (0..<(DeckRequest.knownTermsLimit + 50)).map { "word\($0)" }
        let message = request(known: known).userMessage
        XCTAssertTrue(message.contains("word0, word1"))
        XCTAssertTrue(message.contains("word\(DeckRequest.knownTermsLimit - 1)"))
        XCTAssertFalse(message.contains("word\(DeckRequest.knownTermsLimit),"))
        XCTAssertFalse(message.contains("word\(DeckRequest.knownTermsLimit + 49)"))
    }

    func testNoKnownTermsLineWhenBaseIsEmpty() {
        XCTAssertFalse(request(known: []).userMessage.contains("already has"))
    }

    // MARK: - Схема

    func testSchemaIsValidJSONAndStrict() throws {
        let object = try JSONSerialization.jsonObject(
            with: Data(DeckRequest.outputSchemaJSON.utf8)) as? [String: Any]
        let schema = try XCTUnwrap(object)
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)

        let notes = try XCTUnwrap((schema["properties"] as? [String: Any])?["notes"] as? [String: Any])
        let item = try XCTUnwrap(notes["items"] as? [String: Any])
        XCTAssertEqual(item["additionalProperties"] as? Bool, false)
        // Structured outputs требует перечислить все свойства как обязательные.
        let required = Set(try XCTUnwrap(item["required"] as? [String]))
        let properties = Set(try XCTUnwrap(item["properties"] as? [String: Any]).keys)
        XCTAssertEqual(required, properties)
    }

    func testSchemaPartsOfSpeechMatchTheApp() throws {
        let object = try JSONSerialization.jsonObject(
            with: Data(DeckRequest.outputSchemaJSON.utf8)) as? [String: Any]
        let notes = (object?["properties"] as? [String: Any])?["notes"] as? [String: Any]
        let items = notes?["items"] as? [String: Any]
        let pos = (items?["properties"] as? [String: Any])?["partOfSpeech"] as? [String: Any]
        let allowed = Set(try XCTUnwrap(pos?["enum"] as? [String]))
        XCTAssertEqual(allowed, Set(PartOfSpeech.allCases.map(\.rawValue)))
    }

    // MARK: - Разбор ответа

    private let response = """
    { "name": "Friends S01E03", "notes": [
      { "term": "hang out", "translation": "тусоваться", "ipa": "/hæŋ aʊt/",
        "partOfSpeech": "phrasal verb", "example": "We hang out here.",
        "exampleTranslation": "Мы тут тусуемся.", "cloze": "We ___ ___ here.", "note": "" }
    ] }
    """

    func testResponseBecomesDeckInClaudeFolder() throws {
        let file = try request().deckFile(fromResponse: response)
        XCTAssertEqual(file.deck.name, "Friends S01E03")
        XCTAssertEqual(file.deck.folder, DeckRequest.folder)
        XCTAssertEqual(file.deck.source, "Friends S01E03")
        XCTAssertEqual(file.notes[0].partOfSpeech, .phrasalVerb)
    }

    func testEmptyOptionalFieldsBecomeNil() throws {
        // Схема требует все поля, и «нет подвоха» приходит пустой строкой.
        let file = try request().deckFile(fromResponse: response)
        XCTAssertNil(file.notes[0].note)
    }

    func testNamelessResponseTakesTheRequestTopic() throws {
        let file = try request(topic: "Job interview").deckFile(fromResponse: """
        { "name": "", "notes": [ { "term": "strength", "translation": "сильная сторона" } ] }
        """)
        XCTAssertEqual(file.deck.name, "Job interview")
    }

    func testEmptyNotesInResponseIsAnError() {
        XCTAssertThrowsError(try request().deckFile(fromResponse: #"{ "name": "X", "notes": [] }"#)) {
            XCTAssertEqual($0 as? DeckParseError, .noNotes)
        }
    }

    func testEstimatesGrowWithTheDeck() {
        XCTAssertGreaterThan(request(count: 40).estimatedOutputTokens,
                             request(count: 10).estimatedOutputTokens)
        XCTAssertGreaterThan(request(subtitles: String(repeating: "line ", count: 5_000))
                                .estimatedInputTokens,
                             request().estimatedInputTokens)
        XCTAssertLessThan(request(count: 40).estimatedOutputTokens, DeckRequest.maxTokens)
    }
}

final class AppLanguageTests: XCTestCase {

    func testSystemLanguageIsPickedWhenKnown() {
        XCTAssertEqual(AppLanguage.resolve(preferred: ["pt-PT", "en-US"]), .portuguese)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["ru_RU"]), .russian)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["pt-BR"]), .portuguese)
    }

    func testFirstKnownLanguageWins() {
        XCTAssertEqual(AppLanguage.resolve(preferred: ["de-DE", "ru-RU", "en-US"]), .russian)
    }

    func testUnknownOrEmptyFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.resolve(preferred: ["de-DE", "ja-JP"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferred: []), .english)
        XCTAssertEqual(AppLanguage.resolve(preferred: [""]), .english)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(AppLanguage.resolve(preferred: ["PT"]), .portuguese)
    }
}

final class CEFRLevelTests: XCTestCase {
    func testOrderAndNextStep() {
        XCTAssertLessThan(CEFRLevel.a2, .b1)
        XCTAssertEqual(CEFRLevel.b1.next, .b2)
        XCTAssertEqual(CEFRLevel.c2.next, .c2, "выше C2 целиться некуда")
    }
}
