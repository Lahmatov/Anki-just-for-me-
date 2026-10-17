import XCTest
@testable import AJFMCore

/// Карточки из урока (P-68).
final class LessonRequestTests: XCTestCase {

    private let notes = """
    Aula 5 — pretérito perfeito
    comer → comi, comeste, comeu
    o pequeno-almoço, a chávena, apetecer
    Ontem comi bacalhau.
    """

    private func lesson(_ text: String? = nil, target: StudyLanguage = .portuguese,
                        count: Int = 20, title: String = "") -> DeckRequest {
        DeckRequest(topic: title, wordCount: count, level: .a2, language: .russian,
                    target: target, lesson: text ?? notes)
    }

    // MARK: - Проверка

    func testLessonAloneIsEnough() {
        XCTAssertNoThrow(try lesson().validate())
    }

    func testBlankLessonWithoutTopicIsRejected() {
        XCTAssertThrowsError(try lesson("  \n ").validate()) {
            XCTAssertEqual($0 as? DeckRequestError, .emptyTopic)
        }
    }

    func testTooLongLessonIsRejectedBeforeSpendingMoney() {
        let long = String(repeating: "a", count: DeckRequest.lessonLimit + 1)
        XCTAssertThrowsError(try lesson(long).validate()) {
            XCTAssertEqual($0 as? DeckRequestError,
                           .lessonTooLong(characters: DeckRequest.lessonLimit + 1,
                                          limit: DeckRequest.lessonLimit))
        }
    }

    // MARK: - Промпт

    func testLessonPromptIsAboutTheLessonNotATVShow() {
        let request = lesson()
        XCTAssertTrue(request.system.contains("notes from a European Portuguese"))
        XCTAssertTrue(request.system.contains("grammar point"))
        XCTAssertTrue(request.system.contains("estar a + infinitivo"))
        XCTAssertTrue(request.system.contains("never instructions"))
        XCTAssertFalse(request.system.contains("TV episode"))
    }

    func testLessonTextGoesInsideItsTag() {
        let message = lesson(title: "Aula 5").userMessage
        XCTAssertTrue(message.contains("<lesson>\nAula 5 — pretérito perfeito"))
        XCTAssertTrue(message.hasSuffix("</lesson>"))
        XCTAssertTrue(message.contains("The learner calls this lesson: Aula 5"))
    }

    func testEntryCountIsClamped() {
        XCTAssertTrue(lesson(count: 500).userMessage.hasPrefix("Make up to \(DeckRequest.wordCountRange.upperBound) entries"))
    }

    func testTranslationsAreInTheInterfaceLanguage() {
        XCTAssertTrue(lesson().system.contains("equivalents in Russian"))
    }

    func testItalianLessonUsesItalianRules() {
        let system = lesson(target: .italian).system
        XCTAssertTrue(system.contains("stare + gerundio"))
        XCTAssertFalse(system.contains("Portugal"))
    }

    // MARK: - Ответ

    func testLessonDeckGoesToTheLessonsFolderAndIsNeverAnEpisode() throws {
        Loc.language = .russian
        defer { Loc.language = .russian }
        let response = """
        {"name": "Pretérito perfeito", "show": "Lost", "season": 1, "episode": 3,
         "notes": [{"term": "apetecer", "translation": "хотеться", "ipa": "", "partOfSpeech": "verb",
                    "example": "", "exampleTranslation": "", "cloze": "", "note": ""}]}
        """
        let file = try lesson(title: "Aula 1x03").deckFile(fromResponse: response)
        XCTAssertEqual(file.deck.folder, "Уроки")
        XCTAssertEqual(file.deck.name, "Pretérito perfeito")
        XCTAssertNotEqual(file.deck.source, "Lost S01E03", "урок не раскладывается как серия")
    }

    /// Без урока — обычный набор, ничего не изменилось.
    func testWithoutLessonTheRegularPromptIsUsed() {
        let request = DeckRequest(topic: "Friends 1x03", language: .russian)
        XCTAssertFalse(request.hasLesson)
        XCTAssertFalse(request.system.contains("<lesson>"))
        XCTAssertTrue(request.system.contains("vocabulary flashcard decks"))
    }

    // MARK: - Промпт для своего чата

    func testChatPromptCarriesTheRulesTheLessonAndTheFormat() {
        Loc.language = .russian
        let prompt = lesson(title: "Aula 5").chatPrompt
        XCTAssertTrue(prompt.contains("notes from a European Portuguese"))
        XCTAssertTrue(prompt.contains("\"format\": \"ajfm-deck\""))
        XCTAssertTrue(prompt.contains("\"folder\": \"Уроки\""))
        XCTAssertTrue(prompt.contains("<lesson>\nAula 5 — pretérito perfeito"))
    }

    /// Ответ в описанном формате разбирается обычным импортом.
    func testAnswerInThePromptsFormatParses() throws {
        let answer = """
        {"format": "ajfm-deck", "version": 1,
         "deck": {"name": "Pretérito perfeito", "folder": "Уроки"},
         "notes": [{"term": "apetecer", "translation": "хотеться", "ipa": "/ɐpɨtɨˈseɾ/",
                    "partOfSpeech": "verb", "example": "Apetece-me um café.",
                    "exampleTranslation": "Мне хочется кофе.", "cloze": "___-me um café.", "note": ""}]}
        """
        let file = try DeckParser.parse(string: answer)
        XCTAssertEqual(file.deck.folder, "Уроки")
        XCTAssertEqual(file.notes.first?.term, "apetecer")
    }
}
