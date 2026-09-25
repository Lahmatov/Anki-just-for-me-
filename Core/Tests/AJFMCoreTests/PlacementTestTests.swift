import XCTest
@testable import AJFMCore

final class PlacementTestTests: XCTestCase {

    private var realWords: [String] { PlacementTest.bands.flatMap(\.words) }

    /// «Знаю» на полосах из `known`, «не знаю» на остальных;
    /// на выдумки — «знаю» на первые `falseAlarms`.
    private func answers(known: Set<Int>, falseAlarms: Int = 0) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for (index, band) in PlacementTest.bands.enumerated() {
            for word in band.words { result[word] = known.contains(index) }
        }
        for (index, word) in PlacementTest.pseudowords.enumerated() {
            result[word] = index < falseAlarms
        }
        return result
    }

    // MARK: - Состав

    func testBandsAreContiguous() {
        let bands = PlacementTest.bands
        XCTAssertEqual(bands.first?.lower, 1)
        for (previous, next) in zip(bands, bands.dropFirst()) {
            XCTAssertEqual(next.lower, previous.upper + 1)
        }
        XCTAssertEqual(PlacementTest.maxEstimate, 20_000)
    }

    func testNoPseudowordIsAlsoARealTestWord() {
        XCTAssertTrue(Set(PlacementTest.pseudowords).isDisjoint(with: realWords))
    }

    func testNoDuplicates() {
        let all = PlacementTest.allItems.map(\.word)
        XCTAssertEqual(Set(all).count, all.count)
        XCTAssertEqual(all.count, 36 + 16)
    }

    func testOrderIsReproducibleAndStartsEasy() {
        let first = PlacementTest.items(seed: 42)
        XCTAssertEqual(first, PlacementTest.items(seed: 42))
        XCTAssertEqual(Set(first), Set(PlacementTest.allItems))
        XCTAssertEqual(first.prefix(2).map(\.word), ["worry", "laugh"])
        XCTAssertTrue(first.prefix(2).allSatisfy(\.isReal))
        XCTAssertNotEqual(first, PlacementTest.items(seed: 43))
    }

    // MARK: - Оценка

    func testKnowsEverythingHonestly() {
        let result = PlacementTest.score(answers(known: Set(0..<6)))
        XCTAssertEqual(result.estimatedWords, 20_000)
        XCTAssertEqual(result.level, .c2)
        XCTAssertTrue(result.isReliable)
    }

    func testKnowsNothing() {
        let result = PlacementTest.score(answers(known: []))
        XCTAssertEqual(result.estimatedWords, 0)
        XCTAssertEqual(result.level, .a1)
        XCTAssertTrue(result.isReliable, "честное «не знаю» — тоже надёжный результат")
    }

    func testTopBandOnlyIsA2() {
        let result = PlacementTest.score(answers(known: [0]))
        XCTAssertEqual(result.estimatedWords, 1_000)
        XCTAssertEqual(result.level, .a2)
    }

    func testTwoTopBandsReachB1() {
        XCTAssertEqual(PlacementTest.score(answers(known: [0, 1])).level, .b1)
    }

    func testThreeBandsReachB2AndFourReachC1() {
        XCTAssertEqual(PlacementTest.score(answers(known: [0, 1, 2])).estimatedWords, 4_000)
        XCTAssertEqual(PlacementTest.score(answers(known: [0, 1, 2])).level, .b2)
        XCTAssertEqual(PlacementTest.score(answers(known: [0, 1, 2, 3])).level, .c1)
    }

    func testSayingYesToEverythingScoresZero() {
        // Главная защита теста: «знаю» на всё — не C2, а ноль.
        let result = PlacementTest.score(answers(known: Set(0..<6), falseAlarms: 16))
        XCTAssertEqual(result.falseAlarmRate, 1)
        XCTAssertEqual(result.estimatedWords, 0)
        XCTAssertFalse(result.isReliable)
    }

    func testFalseAlarmsDiscountHits() {
        // 4 из 16 выдумок — «знаю» (25%). Полоса 1 целиком — поправка
        // её не трогает; полоса 2 наполовину: (0.5 − 0.25) / 0.75 = 1/3.
        var given = answers(known: [0], falseAlarms: 4)
        for word in PlacementTest.bands[1].words.prefix(3) { given[word] = true }

        let result = PlacementTest.score(given)
        XCTAssertEqual(result.falseAlarmRate, 0.25, accuracy: 1e-9)
        XCTAssertEqual(result.hitRates[1], 0.5, accuracy: 1e-9)
        XCTAssertEqual(result.estimatedWords, 1_333)
        XCTAssertTrue(result.isReliable, "ровно на пороге — ещё надёжно")
    }

    func testTooManyFalseAlarmsIsUnreliable() {
        let result = PlacementTest.score(answers(known: [0, 1], falseAlarms: 5))
        XCTAssertFalse(result.isReliable)
    }

    func testEmptyAnswersAreUnreliableZero() {
        let result = PlacementTest.score([:])
        XCTAssertEqual(result.estimatedWords, 0)
        XCTAssertFalse(result.isReliable, "без выдумок проверить честность нечем")
    }

    func testUnansweredWordsAreIgnored() {
        // Отвечено только на слова первой полосы и выдумки: пропуски
        // не должны считаться «не знаю».
        var given: [String: Bool] = [:]
        for word in PlacementTest.bands[0].words { given[word] = true }
        for word in PlacementTest.pseudowords { given[word] = false }
        XCTAssertEqual(PlacementTest.score(given).estimatedWords, 1_000)
    }

    func testLevelThresholds() {
        XCTAssertEqual(PlacementTest.level(forEstimatedWords: 0), .a1)
        XCTAssertEqual(PlacementTest.level(forEstimatedWords: 999), .a1)
        XCTAssertEqual(PlacementTest.level(forEstimatedWords: 1_999), .a2)
        XCTAssertEqual(PlacementTest.level(forEstimatedWords: 3_999), .b1)
        XCTAssertEqual(PlacementTest.level(forEstimatedWords: 6_999), .b2)
        XCTAssertEqual(PlacementTest.level(forEstimatedWords: 11_999), .c1)
        XCTAssertEqual(PlacementTest.level(forEstimatedWords: 12_000), .c2)
        XCTAssertEqual(PlacementTest.level(forEstimatedWords: -5), .a1)
    }
}
