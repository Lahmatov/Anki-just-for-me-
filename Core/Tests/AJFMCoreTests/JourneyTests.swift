import XCTest
@testable import AJFMCore

final class JourneyTests: XCTestCase {

    // MARK: - Карта

    func testMapHasThirtyStopsFromStartToFinish() {
        XCTAssertEqual(Journey.stops.count, 30)
        XCTAssertEqual(Journey.stops.first?.kind, .start)
        XCTAssertEqual(Journey.stops.last?.kind, .finish)
        XCTAssertEqual(Journey.stops.first?.threshold, 0)
    }

    func testThresholdsStrictlyIncrease() {
        for (previous, next) in zip(Journey.stops, Journey.stops.dropFirst()) {
            XCTAssertGreaterThan(next.threshold, previous.threshold, "остановка \(next.index)")
        }
    }

    /// Пороги закреплены числами: изменение сдвинет фишку у всех, кто уже
    /// в пути, — это должно быть осознанным решением, а не случайностью.
    func testThresholdsArePinned() {
        let thresholds = Journey.stops.map(\.threshold)
        XCTAssertEqual(Array(thresholds.prefix(6)), [0, 10, 25, 50, 75, 100])
        XCTAssertEqual(thresholds[11], 500)
        XCTAssertEqual(thresholds[15], 1000)
        XCTAssertEqual(thresholds[20], 2000)
        XCTAssertEqual(thresholds.last, 10000)
    }

    func testChestsAreTheRoundMilestones() {
        let chests = Journey.stops.filter { $0.kind == .chest }.map(\.threshold)
        XCTAssertEqual(chests, [100, 250, 500, 1000, 2000, 3000, 5000, 7000])
    }

    func testEveryChestThresholdIsAStop() {
        // Веха, которой нет среди остановок, молча не праздновалась бы никогда.
        for chest in Journey.chestThresholds {
            XCTAssertTrue(Journey.thresholds.contains(chest), "\(chest)")
        }
    }

    func testChestsAreNotTooFarApart() {
        // Больше семи остановок без праздника — и карта перестаёт радовать.
        let indices = Journey.stops.filter { Journey.isMilestone($0) }.map(\.index)
        for (previous, next) in zip([0] + indices, indices) {
            XCTAssertLessThanOrEqual(next - previous, 7, "между \(previous) и \(next)")
        }
    }

    func testStopTitleIsTheWordCount() {
        XCTAssertEqual(Journey.stops[5].title, Counted.words(100))
        XCTAssertNotEqual(Journey.stops[0].title, Counted.words(0), "старт называется стартом")
    }

    // MARK: - Серии

    func testEpisodesEquivalentRoundsToNearest() {
        XCTAssertEqual(Journey.episodes(forWords: 100), 7)   // 6,67
        XCTAssertEqual(Journey.episodes(forWords: 150), 10)
        XCTAssertEqual(Journey.episodes(forWords: 1000), 67) // 66,67
    }

    func testFewWordsAreAtLeastOneEpisode() {
        XCTAssertEqual(Journey.episodes(forWords: 1), 1)
        XCTAssertEqual(Journey.episodes(forWords: 10), 1)
    }

    func testNoWordsAreNoEpisodes() {
        XCTAssertEqual(Journey.episodes(forWords: 0), 0)
        XCTAssertEqual(Journey.episodes(forWords: -5), 0)
    }

    // MARK: - Положение

    func testZeroWordsStandsAtStart() {
        let position = Journey.position(words: 0)
        XCTAssertEqual(position.stopIndex, 0)
        XCTAssertEqual(position.wordsToNext, 10)
        XCTAssertEqual(position.fraction, 0)
        XCTAssertFalse(position.isFinished)
    }

    func testReachingThresholdExactlyArrivesAtStop() {
        let position = Journey.position(words: 100)
        XCTAssertEqual(position.stopIndex, 5)
        XCTAssertEqual(position.wordsIntoLeg, 0)
        XCTAssertEqual(position.legLength, 50)
    }

    func testOneWordShortStaysOnPreviousStop() {
        let position = Journey.position(words: 99)
        XCTAssertEqual(position.stopIndex, 4)
        XCTAssertEqual(position.wordsToNext, 1)
    }

    func testFractionInsideLeg() {
        let position = Journey.position(words: 125)
        XCTAssertEqual(position.stopIndex, 5)
        XCTAssertEqual(position.fraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(position.words, 125)
    }

    func testFinishIsTheEnd() {
        let position = Journey.position(words: 10000)
        XCTAssertEqual(position.stopIndex, 29)
        XCTAssertTrue(position.isFinished)
        XCTAssertEqual(position.wordsToNext, 0)
        XCTAssertEqual(position.fraction, 1)
    }

    func testBeyondFinishStaysOnFinish() {
        let position = Journey.position(words: 25000)
        XCTAssertEqual(position.stopIndex, 29)
        XCTAssertEqual(position.words, 25000, "число слов не обрезается — оно честное")
    }

    func testNegativeWordsStandAtStart() {
        XCTAssertEqual(Journey.position(words: -10).stopIndex, 0)
        XCTAssertEqual(Journey.position(words: -10).words, 0)
    }

    func testHugeWordCountDoesNotCrash() {
        XCTAssertEqual(Journey.position(words: .max).stopIndex, 29)
    }

    func testStopNeverGoesBackAsWordsGrow() {
        var previous = 0
        for words in 0...10_500 {
            let index = Journey.position(words: words).stopIndex
            XCTAssertGreaterThanOrEqual(index, previous, "слов: \(words)")
            previous = index
        }
    }

    // MARK: - Праздники

    func testFirstLaunchDoesNotCelebrateOldProgress() {
        XCTAssertNil(Journey.stopToCelebrate(celebrated: -1, reached: 20))
    }

    func testNoNewStopNoCelebration() {
        XCTAssertNil(Journey.stopToCelebrate(celebrated: 5, reached: 5))
    }

    func testChestIsCelebrated() {
        XCTAssertEqual(Journey.stopToCelebrate(celebrated: 4, reached: 5), 5)
    }

    func testOrdinaryStopIsNotCelebrated() {
        XCTAssertNil(Journey.stopToCelebrate(celebrated: 5, reached: 6))
    }

    func testSeveralChestsAtOnceCelebrateOnlyTheLatest() {
        // Импорт большой колоды: 100, 250 и 500 слов пройдены за раз.
        XCTAssertEqual(Journey.stopToCelebrate(celebrated: 4, reached: 12), 11)
    }

    func testFinishIsCelebrated() {
        XCTAssertEqual(Journey.stopToCelebrate(celebrated: 27, reached: 29), 29)
    }

    func testFallingBackIsNotCelebrated() {
        XCTAssertNil(Journey.stopToCelebrate(celebrated: 11, reached: 6))
    }

    func testOutOfRangeStopDoesNotCrash() {
        XCTAssertEqual(Journey.stopToCelebrate(celebrated: 20, reached: 500), 29)
        XCTAssertNil(Journey.stopToCelebrate(celebrated: 29, reached: 500))
    }
}
