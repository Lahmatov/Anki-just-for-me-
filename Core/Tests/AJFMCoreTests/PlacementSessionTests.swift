import XCTest
@testable import AJFMCore

final class PlacementSessionTests: XCTestCase {

    private func session() -> PlacementSession { PlacementSession(seed: 42) }

    /// Проходит все карточки: настоящие слова — «знаю» и «угадал»,
    /// выдумки — «не знаю».
    private func finishCardsHonestly(_ s: inout PlacementSession) {
        while let item = s.currentItem {
            if item.isReal {
                s.claim(known: true)
                s.confirm(understood: true)
            } else {
                s.claim(known: false)
            }
        }
    }

    // MARK: - Карточки

    func testStartsOnTheFrontOfTheFirstCard() {
        XCTAssertEqual(session().stage, .card(index: 0, revealed: false))
        XCTAssertFalse(session().canGoBack)
    }

    func testDontKnowRecordsAndMovesOnWithoutFlipping() {
        var s = session()
        let word = s.items[0].word
        s.claim(known: false)
        XCTAssertEqual(s.vocabularyAnswers[word], false)
        XCTAssertEqual(s.stage, .card(index: 1, revealed: false))
    }

    func testKnowFlipsTheCardAndWaitsForSelfCheck() {
        var s = session()
        s.claim(known: true)
        XCTAssertEqual(s.stage, .card(index: 0, revealed: true))
        XCTAssertNil(s.vocabularyAnswers[s.items[0].word], "ответ ещё не проверен")
    }

    func testMisunderstoodWordCountsAsUnknown() {
        var s = session()
        let word = s.items[0].word
        s.claim(known: true)
        s.confirm(understood: false)
        XCTAssertEqual(s.vocabularyAnswers[word], false)
        XCTAssertEqual(s.stage, .card(index: 1, revealed: false))
    }

    func testKnowOnAPseudowordIsAFalseAlarmRightAway() throws {
        var s = session()
        let index = try XCTUnwrap(s.items.firstIndex { !$0.isReal })
        while s.currentItem != s.items[index] { s.claim(known: false) }
        s.claim(known: true)
        XCTAssertEqual(s.vocabularyAnswers[s.items[index].word], true)
        // Самопроверки у выдумки нет — только «дальше».
        s.confirm(understood: false)
        XCTAssertEqual(s.stage, .card(index: index, revealed: true))
        s.next()
        XCTAssertEqual(s.stage, .card(index: index + 1, revealed: false))
    }

    func testNextDoesNothingOnARealWord() {
        var s = session()
        s.claim(known: true)
        s.next()
        XCTAssertEqual(s.stage, .card(index: 0, revealed: true))
    }

    // MARK: - Назад

    func testBackFromTheRevealedSideReturnsToTheFront() {
        var s = session()
        s.claim(known: true)
        s.goBack()
        XCTAssertEqual(s.stage, .card(index: 0, revealed: false))
    }

    func testBackFromAFrontUndoesThePreviousAnswer() {
        var s = session()
        let first = s.items[0].word
        s.claim(known: false)
        s.goBack()
        XCTAssertEqual(s.stage, .card(index: 0, revealed: false))
        XCTAssertNil(s.vocabularyAnswers[first])
    }

    func testBackOnTheFirstFrontDoesNothing() {
        var s = session()
        s.goBack()
        XCTAssertEqual(s.stage, .card(index: 0, revealed: false))
    }

    func testBackUndoesAPseudowordFalseAlarm() throws {
        var s = session()
        let index = try XCTUnwrap(s.items.firstIndex { !$0.isReal })
        while s.currentItem != s.items[index] { s.claim(known: false) }
        s.claim(known: true)
        s.goBack()
        XCTAssertNil(s.vocabularyAnswers[s.items[index].word])
    }

    func testBackFromTheFirstQuestionReturnsToTheLastCard() {
        var s = session()
        finishCardsHonestly(&s)
        XCTAssertEqual(s.stage, .grammar(index: 0))
        s.goBack()
        XCTAssertEqual(s.stage, .card(index: s.items.count - 1, revealed: false))
        XCTAssertNil(s.vocabularyAnswers[s.items[s.items.count - 1].word])
    }

    func testBackBetweenQuestionsUndoesTheAnswer() {
        var s = session()
        finishCardsHonestly(&s)
        let first = s.questions[0]
        s.answer(first.answer)
        s.goBack()
        XCTAssertEqual(s.stage, .grammar(index: 0))
        XCTAssertNil(s.grammarAnswers[first.id])
    }

    // MARK: - Грамматика и итог

    func testGrammarFollowsTheCards() {
        var s = session()
        finishCardsHonestly(&s)
        XCTAssertEqual(s.completedSteps, s.items.count)
        XCTAssertEqual(s.currentOptions.count, 4)
        XCTAssertEqual(Set(s.currentOptions), Set(s.questions[0].options))
    }

    func testPerfectRunGivesC2() {
        var s = session()
        finishCardsHonestly(&s)
        while let question = s.currentQuestion { s.answer(question.answer) }
        XCTAssertEqual(s.stage, .finished)
        XCTAssertEqual(s.outcome.vocabulary.level, .c2)
        XCTAssertEqual(s.outcome.grammar, .c2)
        XCTAssertEqual(s.outcome.level, .c2)
        XCTAssertEqual(s.completedSteps, s.totalSteps)
    }

    func testWeakGrammarPullsTheLevelDown() {
        var s = session()
        finishCardsHonestly(&s)
        while let question = s.currentQuestion {
            s.answer(question.level <= .a2 ? question.answer : "wrong")
        }
        XCTAssertEqual(s.outcome.grammar, .a2)
        // Словарь C2 и грамматика A2 — в среднем B2, округление вниз.
        XCTAssertEqual(s.outcome.level, .b2)
    }

    func testSkippedGrammarLeavesVocabularyOnly() {
        var s = session()
        finishCardsHonestly(&s)
        s.skipGrammar()
        XCTAssertEqual(s.stage, .finished)
        XCTAssertNil(s.outcome.grammar)
        XCTAssertEqual(s.outcome.level, s.outcome.vocabulary.level)
        XCTAssertEqual(s.totalSteps, s.items.count)
    }

    func testSkipIsIgnoredDuringCards() {
        var s = session()
        s.skipGrammar()
        XCTAssertFalse(s.skippedGrammar)
        XCTAssertEqual(s.stage, .card(index: 0, revealed: false))
    }

    func testSelfCheckLowersTheEstimate() {
        // Сказал «знаю» на всё, но половину понял неверно — оценка ниже,
        // чем у того, кто понял всё.
        var honest = session()
        finishCardsHonestly(&honest)
        var mixed = session()
        var flip = false
        while let item = mixed.currentItem {
            if item.isReal {
                mixed.claim(known: true)
                mixed.confirm(understood: flip)
                flip.toggle()
            } else {
                mixed.claim(known: false)
            }
        }
        XCTAssertLessThan(mixed.outcome.vocabulary.estimatedWords,
                          honest.outcome.vocabulary.estimatedWords)
    }
}

final class GrammarTestTests: XCTestCase {

    private func answers(correctUpTo level: CEFRLevel?) -> [Int: Bool] {
        Dictionary(uniqueKeysWithValues: GrammarTest.questions.map { question in
            (question.id, level.map { top in question.level <= top } ?? false)
        })
    }

    func testThreeQuestionsPerLevelWithFourUniqueOptions() {
        for level in CEFRLevel.allCases {
            XCTAssertEqual(GrammarTest.questions.filter { $0.level == level }.count,
                           GrammarTest.perLevel, level.rawValue)
        }
        for question in GrammarTest.questions {
            XCTAssertEqual(question.options.count, 4, question.prompt)
            XCTAssertEqual(Set(question.options).count, 4, question.prompt)
            XCTAssertTrue(question.prompt.contains("___"), question.prompt)
        }
    }

    func testIdentifiersAreUnique() {
        let ids = GrammarTest.questions.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testShuffleIsReproducibleAndKeepsTheOptions() {
        let question = GrammarTest.questions[4]
        let once = GrammarTest.shuffledOptions(of: question, seed: 7)
        XCTAssertEqual(once, GrammarTest.shuffledOptions(of: question, seed: 7))
        XCTAssertEqual(Set(once), Set(question.options))
    }

    func testCorrectAnswerIsNotAlwaysFirstOnScreen() {
        let firsts = GrammarTest.questions.map { GrammarTest.shuffledOptions(of: $0, seed: 1)[0] }
        let answers = GrammarTest.questions.map(\.answer)
        XCTAssertNotEqual(firsts, answers)
    }

    func testLevelsFromCleanRuns() {
        XCTAssertEqual(GrammarTest.level(answers: answers(correctUpTo: nil)), .a1)
        XCTAssertEqual(GrammarTest.level(answers: [:]), .a1)
        for level in CEFRLevel.allCases {
            XCTAssertEqual(GrammarTest.level(answers: answers(correctUpTo: level)), level)
        }
    }

    func testOneSlipLowDoesNotCollapseTheResult() {
        // A2 решена на один из трёх, остальное до B2 — чисто.
        var given = answers(correctUpTo: .b2)
        let a2 = GrammarTest.questions.filter { $0.level == .a2 }.map(\.id)
        given[a2[0]] = false
        given[a2[1]] = false
        XCTAssertEqual(GrammarTest.level(answers: given), .b2)
    }

    func testLuckyHighAnswersWithoutTheBasicsDoNotCount() {
        // Верно только C2 — похоже на угадывание: совокупная доля мала.
        let given = Dictionary(uniqueKeysWithValues: GrammarTest.questions.map {
            ($0.id, $0.level == .c2)
        })
        XCTAssertEqual(GrammarTest.level(answers: given), .a1)
    }

    func testCombinedRoundsDown() {
        XCTAssertEqual(GrammarTest.combined(vocabulary: .b2, grammar: .b1), .b1)
        XCTAssertEqual(GrammarTest.combined(vocabulary: .c2, grammar: .a2), .b2)
        XCTAssertEqual(GrammarTest.combined(vocabulary: .a1, grammar: .c2), .b1)
        XCTAssertEqual(GrammarTest.combined(vocabulary: .b1, grammar: .b1), .b1)
        XCTAssertEqual(GrammarTest.combined(vocabulary: .c1, grammar: nil), .c1)
    }
}

final class PlacementGlossaryTests: XCTestCase {
    func testEveryRealWordHasAGlossInEveryLanguage() {
        for word in PlacementTest.bands.flatMap(\.words) {
            for language in AppLanguage.allCases {
                let gloss = PlacementTest.gloss(for: word, language: language)
                XCTAssertFalse((gloss ?? "").isEmpty, "\(word) / \(language.rawValue)")
            }
        }
    }

    func testPseudowordsHaveNoGloss() {
        for word in PlacementTest.pseudowords {
            XCTAssertNil(PlacementTest.gloss(for: word, language: .russian), word)
        }
    }
}
