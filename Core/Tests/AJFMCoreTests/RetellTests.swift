import XCTest
@testable import AJFMCore

final class RetellPromptTests: XCTestCase {

    func testSystemPromptForbidsRelyingOnModelMemory() {
        // Вся фича держится на этом: без запрета модель начинает
        // сообщать об ошибках, которых не было.
        let system = RetellPrompt.system(for: .russian)
        XCTAssertTrue(system.contains("ONLY by the attached"))
        XCTAssertTrue(system.contains("Do not rely on your own knowledge"))
    }

    func testSystemPromptRequiresQuotes() {
        XCTAssertTrue(RetellPrompt.system(for: .russian).contains("short quote from the subtitles"))
    }

    func testSystemPromptAccountsForSpeechRecognitionErrors() {
        // Акцент не должен превращаться в «ошибку понимания».
        XCTAssertTrue(RetellPrompt.system(for: .russian).contains("mayBeMisheard"))
    }

    func testSystemPromptLimitsTheNumberOfRemarks() {
        XCTAssertTrue(RetellPrompt.system(for: .russian).contains("No more than three"))
    }

    func testSystemPromptSeparatesUnderstandingFromLanguage() {
        XCTAssertTrue(RetellPrompt.system(for: .russian).contains("never mix them"))
    }

    func testExplanationsComeInTheLearnersLanguage() {
        XCTAssertTrue(RetellPrompt.system(for: .russian).contains("native language is Russian"))
        XCTAssertTrue(RetellPrompt.system(for: .portuguese).contains("European Portuguese"))
        XCTAssertTrue(RetellPrompt.system(for: .english)
            .contains("explanation (claim, comment, why, fluencyNote, topPriorities, "
                      + "translation) in English"))
    }

    func testDefaultSystemPromptFollowsTheInterface() {
        defer { Loc.language = .russian }
        Loc.language = .portuguese
        XCTAssertEqual(RetellPrompt.system, RetellPrompt.system(for: .portuguese))
    }

    func testUserMessageCarriesBothSources() {
        let message = RetellPrompt.userMessage(
            subtitles: "You have no leverage.",
            retell: "He said he has no power.",
            episodeTitle: "Breaking Bad S03E05",
            watchedUpTo: nil)

        XCTAssertTrue(message.contains("You have no leverage."))
        XCTAssertTrue(message.contains("He said he has no power."))
        XCTAssertTrue(message.contains("Breaking Bad S03E05"))
        XCTAssertTrue(message.contains("<subtitles>"))
        XCTAssertTrue(message.contains("<retelling>"))
    }

    func testUserMessageMentionsTrimmingWhenWatchedPartially() {
        let message = RetellPrompt.userMessage(
            subtitles: "...", retell: "...", episodeTitle: nil, watchedUpTo: 1500)
        XCTAssertTrue(message.contains("up to minute 25"))
    }

    func testUserMessageWorksWithoutOptionalParts() {
        let message = RetellPrompt.userMessage(
            subtitles: "sub", retell: "retell", episodeTitle: nil, watchedUpTo: nil)
        XCTAssertFalse(message.contains("Episode:"))
        XCTAssertFalse(message.contains("watched up to"))
    }

    func testTokenEstimateIsInTheRightBallpark() {
        // Субтитры серии на 45 минут — около 12 тысяч токенов.
        let episode = String(repeating: "a", count: 42_000)
        let estimate = RetellPrompt.estimateTokens(episode)
        XCTAssertGreaterThan(estimate, 8_000)
        XCTAssertLessThan(estimate, 16_000)
        XCTAssertGreaterThan(RetellPrompt.estimateTokens(""), 0)
    }
}

final class RetellReportTests: XCTestCase {

    private func sampleReport() -> RetellReport {
        RetellReport(
            understanding: .init(
                correct: [.init(claim: "Уолт отказался от денег", quote: "I don't want it.")],
                incorrect: [.init(
                    claim: "Джесси сдал его полиции",
                    quote: "I'm not going to the cops.",
                    comment: "Он только пригрозил",
                    mayBeMisheard: false)],
                missed: [.init(claim: "Линия с Хэнком", quote: "Hank found the RV.")],
                coverage: 0.7),
            language: .init(
                grammar: [.init(
                    said: "he don't know", better: "he doesn't know",
                    why: "третье лицо единственного числа")],
                vocabulary: [.init(said: "bad guy", better: "antagonist")],
                fluencyNote: "Много «like» между фразами.",
                suggestedWords: [
                    .init(
                        term: "antagonist", translation: "злодей, антагонист",
                        example: "He is the antagonist here.", insteadOf: "bad guy")
                ]),
            topPriorities: ["Третье лицо единственного числа"])
    }

    func testCoveragePercent() {
        XCTAssertEqual(sampleReport().understanding.coveragePercent, 70)
    }

    func testSummaryLine() {
        let line = sampleReport().summaryLine
        XCTAssertTrue(line.contains("70%"))
        XCTAssertTrue(line.contains("2"), "одна грамматическая и одна лексическая правка")
    }

    func testReportSurvivesJSONRoundTrip() throws {
        let report = sampleReport()
        let restored = try JSONDecoder().decode(
            RetellReport.self, from: try JSONEncoder().encode(report))
        XCTAssertEqual(restored, report)
    }

    func testTruncatedAnswerIsRejected() {
        // Ответ, оборвавшийся по лимиту токенов, декодировался бы в «отчёт»
        // без единой ошибки — и попадал в историю, портя статистику.
        XCTAssertThrowsError(
            try JSONDecoder().decode(RetellReport.self, from: Data("{}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(
            RetellReport.self, from: Data("{\"topPriorities\": []}".utf8)))
    }

    func testPartialAnswerWithUnderstandingIsAccepted() throws {
        // А вот разбор, где есть понимание, но нет блока языка, — рабочий:
        // терять его из-за пропущенного поля было бы обиднее.
        let report = try JSONDecoder().decode(RetellReport.self, from: Data("""
        {"understanding": {"coverage": 0.6}}
        """.utf8))
        XCTAssertEqual(report.understanding.coverage, 0.6)
        XCTAssertTrue(report.language.grammar.isEmpty)
    }

    func testDecodesTheShapeTheModelIsAskedFor() throws {
        // Если схема в промпте и структура разойдутся, разбор будет падать
        // уже после того, как деньги за запрос списаны.
        let json = """
        {
          "understanding": {
            "correct": [{"claim": "a", "quote": "q"}],
            "incorrect": [{"claim": "b", "quote": "q", "comment": "c", "mayBeMisheard": true}],
            "missed": [{"claim": "d"}],
            "coverage": 0.5
          },
          "language": {
            "grammar": [{"said": "x", "better": "y", "why": "z"}],
            "vocabulary": [{"said": "p", "better": "q"}],
            "fluencyNote": null,
            "suggestedWords": [{"term": "t", "translation": "п", "example": "e", "insteadOf": "i"}]
          },
          "topPriorities": ["один"]
        }
        """
        let report = try JSONDecoder().decode(RetellReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.understanding.coverage, 0.5)
        XCTAssertEqual(report.understanding.incorrect.first?.mayBeMisheard, true)
        XCTAssertNil(report.language.fluencyNote)
        XCTAssertEqual(report.language.suggestedWords.first?.insteadOf, "i")
    }

    // MARK: - Главный контур: ошибки превращаются в карточки

    func testReportBecomesADeck() throws {
        let deck = try XCTUnwrap(sampleReport().makeDeck(name: "Пересказ S03E05"))

        XCTAssertEqual(deck.format, DeckFile.formatID)
        XCTAssertEqual(deck.deck.name, "Пересказ S03E05")
        // Одно недостающее слово плюс одна грамматическая правка.
        XCTAssertEqual(deck.notes.count, 2)
    }

    func testSuggestedWordBecomesACardWithContext() throws {
        let deck = try XCTUnwrap(sampleReport().makeDeck(name: "X"))
        let word = try XCTUnwrap(deck.notes.first { $0.term == "antagonist" })

        XCTAssertEqual(word.translation, "злодей, антагонист")
        XCTAssertEqual(word.example, "He is the antagonist here.")
        XCTAssertEqual(word.note, "Ты сказал «bad guy».")
        XCTAssertEqual(word.tags, ["пересказ", "словарь"])
    }

    func testGrammarMistakeBecomesACard() throws {
        let deck = try XCTUnwrap(sampleReport().makeDeck(name: "X"))
        let rule = try XCTUnwrap(deck.notes.first { $0.term == "he doesn't know" })

        XCTAssertEqual(rule.note, "Было: «he don't know»")
        XCTAssertEqual(rule.tags, ["пересказ", "грамматика"])
    }

    func testGeneratedDeckIsValidForImport() throws {
        let deck = try XCTUnwrap(sampleReport().makeDeck(name: "Пересказ", folder: "Пересказы"))
        // Набор из разбора должен проходить тот же импорт, что и присланный файл.
        let parsed = try DeckParser.parse(data: try DeckParser.encode(deck))
        let plan = ImportPlanner.plan(file: parsed, existingTerms: [:])

        XCTAssertEqual(plan.folderPath, ["Пересказы"])
        XCTAssertEqual(plan.newNotes.count, 2)
        XCTAssertEqual(plan.scheduler, .fsrs6)
    }

    func testFlawlessRetellMakesNoDeck() {
        let perfect = RetellReport(
            understanding: .init(correct: [], incorrect: [], missed: [], coverage: 1),
            language: .init(
                grammar: [], vocabulary: [], fluencyNote: nil, suggestedWords: []),
            topPriorities: [])
        // Пустой набор создавать незачем — предлагать его было бы шумом.
        XCTAssertNil(perfect.makeDeck(name: "Пересказ"))
    }
}

final class UsageTrackerTests: XCTestCase {

    private func record(_ cost: Double, daysAgo: Int = 0) -> UsageRecord {
        UsageRecord(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            model: "claude-opus-5", inputTokens: 13_000, outputTokens: 1_500, cost: cost)
    }

    func testPricingMatchesPublishedRates() {
        XCTAssertEqual(ClaudeModel.opus5.inputPerMillion, 5)
        XCTAssertEqual(ClaudeModel.opus5.outputPerMillion, 25)
        XCTAssertEqual(ClaudeModel.sonnet5.inputPerMillion, 2)
        XCTAssertEqual(ClaudeModel.haiku45.outputPerMillion, 5)
    }

    func testRealisticRetellCost() {
        // Субтитры серии плюс пересказ — около 13 тысяч токенов на вход.
        let cost = ClaudeModel.opus5.cost(inputTokens: 13_600, outputTokens: 1_500)
        XCTAssertEqual(cost, 0.1055, accuracy: 0.001)

        // Серия в день на самой дорогой модели — около трёх долларов в месяц.
        XCTAssertLessThan(cost * 30, 3.5)
    }

    func testCheaperModelIsActuallyCheaper() {
        let opus = ClaudeModel.opus5.cost(inputTokens: 13_600, outputTokens: 1_500)
        let sonnet = ClaudeModel.sonnet5.cost(inputTokens: 13_600, outputTokens: 1_500)
        XCTAssertLessThan(sonnet, opus / 2)
    }

    func testSummaryCountsOnlyCurrentMonth() {
        let summary = UsageTracker.summary(
            records: [record(1.0), record(2.0), record(5.0, daysAgo: 60)], limit: 10)
        XCTAssertEqual(summary.monthCost, 3.0, accuracy: 0.001)
        XCTAssertEqual(summary.monthRequests, 2)
        XCTAssertEqual(summary.remaining, 7.0, accuracy: 0.001)
        XCTAssertFalse(summary.isOverLimit)
    }

    func testOverLimitIsDetected() {
        let summary = UsageTracker.summary(records: [record(11.0)], limit: 10)
        XCTAssertTrue(summary.isOverLimit)
        XCTAssertEqual(summary.remaining, 0)
        XCTAssertEqual(summary.usedFraction, 1.0)
    }

    func testEmptyHistoryIsFine() {
        let summary = UsageTracker.summary(records: [], limit: 10)
        XCTAssertEqual(summary.monthCost, 0)
        XCTAssertEqual(summary.usedFraction, 0)
    }

    func testRequestIsBlockedWhenItWouldBustTheLimit() {
        let nearLimit = UsageTracker.summary(records: [record(9.95)], limit: 10)
        XCTAssertFalse(UsageTracker.canAfford(
            estimatedInputTokens: 13_000, estimatedOutputTokens: 1_500,
            pricing: ClaudeModel.opus5, summary: nearLimit))

        let plentyLeft = UsageTracker.summary(records: [record(1.0)], limit: 10)
        XCTAssertTrue(UsageTracker.canAfford(
            estimatedInputTokens: 13_000, estimatedOutputTokens: 1_500,
            pricing: ClaudeModel.opus5, summary: plentyLeft))
    }

    func testUnknownModelFallsBackToOpus() {
        XCTAssertEqual(ClaudeModel.pricing(for: "что-то-новое").id, ClaudeModel.opus5.id)
    }
}
