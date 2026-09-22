import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

@MainActor
final class ReviewSessionModelTests: XCTestCase {

    private func makeSession(
        cardTypes: [CardType] = [.recall],
        notes: [NoteData]? = nil,
        settings: AppSettings = AppSettings.default
    ) throws -> (ModelContext, ReviewSessionModel) {
        let context = try TestDB.makeContext()
        let importer = ImportService(context: context)
        let payload = notes ?? [
            NoteData(term: "leverage", translation: "рычаг", synonyms: ["влияние"])
        ]
        try importer.apply(try importer.makePlan(
            from: TestDB.deckFile(cardTypes: cardTypes, notes: payload)))

        let model = ReviewSessionModel(context: context, settings: settings)
        model.load()
        return (context, model)
    }

    func testSessionLoadsDueCards() throws {
        let (_, model) = try makeSession(notes: [
            NoteData(term: "one", translation: "раз"),
            NoteData(term: "two", translation: "два"),
        ])
        XCTAssertEqual(model.cards.count, 2)
        XCTAssertFalse(model.isFinished)
        XCTAssertNotNil(model.current)
        XCTAssertEqual(model.progress, 0)
    }

    func testEmptyDatabaseGivesFinishedSession() throws {
        let context = try TestDB.makeContext()
        let model = ReviewSessionModel(context: context)
        model.load()
        XCTAssertTrue(model.isFinished)
        XCTAssertNil(model.current)
    }

    func testTypedCorrectAnswerIsAccepted() throws {
        let (_, model) = try makeSession()
        model.typedAnswer = "leverage"
        model.reveal()

        XCTAssertTrue(model.isRevealed)
        XCTAssertEqual(model.check?.verdict, .correct)
        XCTAssertEqual(model.stats.correct, 1)
        XCTAssertEqual(model.suggestedGrade, .good)
    }

    func testTypoIsAcceptedButSuggestsHard() throws {
        let (_, model) = try makeSession()
        model.typedAnswer = "leverge"
        model.reveal()

        XCTAssertEqual(model.check?.verdict, .typo)
        XCTAssertEqual(model.stats.typos, 1)
        XCTAssertEqual(model.suggestedGrade, .hard)
    }

    func testSynonymIsAccepted() throws {
        let (_, model) = try makeSession()
        model.typedAnswer = "влияние"
        model.reveal()
        XCTAssertEqual(model.check?.verdict, .correct)
    }

    func testWrongAnswerSuggestsAgain() throws {
        let (_, model) = try makeSession()
        model.typedAnswer = "совершенно не то"
        model.reveal()

        XCTAssertEqual(model.check?.verdict, .wrong)
        XCTAssertEqual(model.stats.wrong, 1)
        XCTAssertEqual(model.suggestedGrade, .again)
    }

    func testSpellingCardIsStrictAboutTypos() throws {
        let (_, model) = try makeSession(cardTypes: [.spelling])
        model.typedAnswer = "leverge"
        model.reveal()
        // Карточка на правописание существует ровно ради точности написания.
        XCTAssertEqual(model.check?.verdict, .wrong)
    }

    func testRecognitionCardOffersChoices() throws {
        let (_, model) = try makeSession(
            cardTypes: [.recognition],
            notes: (1...6).map { NoteData(term: "w\($0)", translation: "перевод \($0)") })

        XCTAssertEqual(model.choices.count, 4)
        let correct = try XCTUnwrap(model.current?.note?.translation)
        XCTAssertTrue(model.choices.contains(correct), "правильный вариант обязан быть среди них")
        XCTAssertEqual(Set(model.choices).count, 4, "варианты не должны повторяться")
    }

    func testChoosingRightOptionCountsAsCorrect() throws {
        let (_, model) = try makeSession(
            cardTypes: [.recognition],
            notes: (1...6).map { NoteData(term: "w\($0)", translation: "перевод \($0)") })
        let correct = try XCTUnwrap(model.current?.note?.translation)

        model.choose(correct)
        XCTAssertEqual(model.check?.verdict, .correct)
        XCTAssertEqual(model.stats.correct, 1)
        XCTAssertTrue(model.isRevealed)
    }

    func testChoosingWrongOptionCountsAsWrong() throws {
        let (_, model) = try makeSession(
            cardTypes: [.recognition],
            notes: (1...6).map { NoteData(term: "w\($0)", translation: "перевод \($0)") })
        let correct = try XCTUnwrap(model.current?.note?.translation)
        let wrong = try XCTUnwrap(model.choices.first { $0 != correct })

        model.choose(wrong)
        XCTAssertEqual(model.check?.verdict, .wrong)
        XCTAssertEqual(model.stats.wrong, 1)
    }

    func testAnswerCannotBeChangedAfterReveal() throws {
        let (_, model) = try makeSession()
        model.typedAnswer = "leverage"
        model.reveal()
        model.typedAnswer = "что-то другое"
        model.reveal()

        XCTAssertEqual(model.stats.answered, 1, "повторная проверка не должна удваивать счёт")
        XCTAssertEqual(model.check?.verdict, .correct)
    }

    func testGradingAdvancesToTheNextCard() throws {
        let (_, model) = try makeSession(notes: [
            NoteData(term: "one", translation: "раз"),
            NoteData(term: "two", translation: "два"),
        ])
        let first = model.current

        model.typedAnswer = model.current?.note?.term ?? ""
        model.reveal()
        model.grade(.good)

        XCTAssertEqual(model.index, 1)
        XCTAssertNotIdentical(model.current, first)
        XCTAssertFalse(model.isRevealed, "новая карточка показывается закрытой")
        XCTAssertEqual(model.typedAnswer, "", "поле ввода очищается")
        XCTAssertNil(model.check)
    }

    func testSessionFinishesAfterLastCard() throws {
        let (_, model) = try makeSession()
        model.typedAnswer = "leverage"
        model.reveal()
        model.grade(.good)

        XCTAssertTrue(model.isFinished)
        XCTAssertNil(model.current)
        XCTAssertEqual(model.progress, 1)
    }

    func testGradingPersistsProgress() throws {
        let (context, model) = try makeSession()
        model.typedAnswer = "leverage"
        model.reveal()
        model.grade(.easy)

        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)
        XCTAssertEqual(card.reps, 1)
        XCTAssertEqual(card.state, .review)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Review>()).count, 1)
    }

    func testListeningCardChecksTheWordItSpeaks() throws {
        let (_, model) = try makeSession(
            cardTypes: [.listening],
            notes: [NoteData(
                term: "leverage", translation: "рычаг",
                example: "You have no leverage at all.")])

        // Озвучивается слово, значит и проверяться должно слово.
        // Если бы проигрывался пример целиком, правильный ответ был бы
        // недостижим: услышал фразу, а ждут одно слово.
        model.typedAnswer = "leverage"
        model.reveal()
        XCTAssertEqual(model.check?.verdict, .correct)
    }

    func testListeningCardForgivesTypos() throws {
        let (_, model) = try makeSession(
            cardTypes: [.listening],
            notes: [NoteData(term: "leverage", translation: "рычаг")])
        model.typedAnswer = "leverge"
        model.reveal()
        // На слух опечатка — не то же самое, что не понял слово.
        XCTAssertEqual(model.check?.verdict, .typo)
    }

    func testPronunciationCardNeedsNoTyping() throws {
        let (_, model) = try makeSession(cardTypes: [.pronunciation])
        XCTAssertFalse(model.current?.type.requiresTyping ?? true)

        model.reveal()
        XCTAssertTrue(model.isRevealed)
        XCTAssertNil(model.check, "самооценку не проверяем автоматически")
        XCTAssertEqual(model.stats.answered, 0)
    }

    func testIntervalsAreShownForEveryGrade() throws {
        let (_, model) = try makeSession()
        for grade in Grade.allCases {
            XCTAssertFalse(model.interval(for: grade).isEmpty)
        }
        XCTAssertEqual(model.intervals.count, 4)
    }

    func testAccuracyReflectsAnswers() throws {
        let (_, model) = try makeSession(notes: [
            NoteData(term: "one", translation: "раз"),
            NoteData(term: "two", translation: "два"),
        ])
        model.typedAnswer = model.current?.note?.term ?? ""
        model.reveal()
        model.grade(.good)

        model.typedAnswer = "мимо"
        model.reveal()

        XCTAssertEqual(model.stats.answered, 2)
        XCTAssertEqual(model.stats.accuracy, 0.5, accuracy: 0.001)
    }
}
