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

    func testEveryFifthStopIsAChest() {
        for stop in Journey.stops.dropFirst().dropLast() {
            XCTAssertEqual(stop.kind == .chest, stop.index % 5 == 0, "остановка \(stop.index)")
        }
    }

    func testThresholdsStrictlyIncrease() {
        for (previous, next) in zip(Journey.stops, Journey.stops.dropFirst()) {
            XCTAssertGreaterThan(next.threshold, previous.threshold, "остановка \(next.index)")
        }
    }

    func testPlacesAreUnique() {
        XCTAssertEqual(Set(Journey.stops.map(\.place)).count, Journey.stops.count)
    }

    /// Пороги закреплены числами: изменение формулы сдвинет фишку у всех,
    /// кто уже в пути, — это должно быть осознанным решением, а не случайностью.
    func testThresholdsArePinned() {
        let thresholds = Journey.stops.map(\.threshold)
        XCTAssertEqual(Array(thresholds.prefix(7)), [0, 5, 10, 15, 20, 25, 35])
        XCTAssertEqual(thresholds[10], 75)
        XCTAssertEqual(thresholds[15], 150)
        XCTAssertEqual(thresholds[20], 250)
        XCTAssertEqual(thresholds[25], 375)
        XCTAssertEqual(Journey.lapLength, 495)
    }

    func testLegLengthGrowsEveryFiveStops() {
        XCTAssertEqual(Journey.legLength(to: 0), 0)
        XCTAssertEqual(Journey.legLength(to: 1), 5)
        XCTAssertEqual(Journey.legLength(to: 5), 5)
        XCTAssertEqual(Journey.legLength(to: 6), 10)
        XCTAssertEqual(Journey.legLength(to: 29), 30)
    }

    // MARK: - Очки

    func testStartedAndMatureWordsBothCount() {
        XCTAssertEqual(Journey.points(startedWords: 10, matureWords: 3), 13)
    }

    func testEmptyProgressGivesZeroPoints() {
        XCTAssertEqual(Journey.points(startedWords: 0, matureWords: 0), 0)
    }

    func testNegativeCountsAreZero() {
        XCTAssertEqual(Journey.points(startedWords: -4, matureWords: -1), 0)
        XCTAssertEqual(Journey.points(startedWords: 5, matureWords: -1), 5)
    }

    func testMatureCannotExceedStarted() {
        XCTAssertEqual(Journey.points(startedWords: 2, matureWords: 7), 4)
    }

    // MARK: - Положение фишки

    func testZeroPointsStandsAtStart() {
        let position = Journey.position(points: 0)
        XCTAssertEqual(position.stopIndex, 0)
        XCTAssertEqual(position.lap, 0)
        XCTAssertEqual(position.reachedStops, 0)
        XCTAssertEqual(position.pointsToNext, 5)
        XCTAssertEqual(position.fraction, 0)
    }

    func testReachingThresholdExactlyArrivesAtStop() {
        let position = Journey.position(points: 5)
        XCTAssertEqual(position.stopIndex, 1)
        XCTAssertEqual(position.pointsIntoLeg, 0)
    }

    func testOnePointShortStaysOnPreviousStop() {
        let position = Journey.position(points: 34)
        XCTAssertEqual(position.stopIndex, 5)
        XCTAssertEqual(position.pointsToNext, 1)
    }

    func testFractionInsideLeg() {
        // Остановка 5 на 25 очках, следующая — на 35.
        let position = Journey.position(points: 30)
        XCTAssertEqual(position.stopIndex, 5)
        XCTAssertEqual(position.legLength, 10)
        XCTAssertEqual(position.fraction, 0.5, accuracy: 1e-9)
    }

    func testLastLegLeadsToFinish() {
        let position = Journey.position(points: 494)
        XCTAssertEqual(position.stopIndex, 28)
        XCTAssertEqual(position.pointsToNext, 1)
    }

    func testFinishStartsNewLap() {
        let position = Journey.position(points: 495)
        XCTAssertEqual(position.lap, 1)
        XCTAssertEqual(position.stopIndex, 0)
        XCTAssertEqual(position.reachedStops, 29)
    }

    func testSecondLapCountsStopsThroughAllLaps() {
        let position = Journey.position(points: 495 + 10)
        XCTAssertEqual(position.lap, 1)
        XCTAssertEqual(position.stopIndex, 2)
        XCTAssertEqual(position.reachedStops, 31)
    }

    func testNegativePointsStandAtStart() {
        XCTAssertEqual(Journey.position(points: -10), Journey.position(points: 0))
    }

    func testHugePointsDoNotCrash() {
        let position = Journey.position(points: 1_000_000)
        XCTAssertEqual(position.lap, 1_000_000 / 495)
        XCTAssertTrue((0..<30).contains(position.stopIndex))
    }

    func testReachedStopsNeverGoesBackAsPointsGrow() {
        var previous = -1
        for points in 0...2_000 {
            let reached = Journey.position(points: points).reachedStops
            XCTAssertGreaterThanOrEqual(reached, previous, "очки \(points)")
            previous = reached
        }
    }

    // MARK: - Праздники

    func testFirstLaunchDoesNotCelebrateOldProgress() {
        XCTAssertNil(Journey.stopToCelebrate(celebrated: -1, reached: 12))
    }

    func testNoNewStopNoCelebration() {
        XCTAssertNil(Journey.stopToCelebrate(celebrated: 4, reached: 4))
    }

    func testChestIsCelebrated() {
        XCTAssertEqual(Journey.stopToCelebrate(celebrated: 4, reached: 5), 5)
    }

    func testOrdinaryStopIsNotCelebrated() {
        XCTAssertNil(Journey.stopToCelebrate(celebrated: 1, reached: 4))
    }

    func testSeveralChestsAtOnceCelebrateOnlyTheLatest() {
        XCTAssertEqual(Journey.stopToCelebrate(celebrated: 1, reached: 12), 10)
    }

    func testFinishIsCelebratedEvenWhenNewLapAlreadyStarted() {
        XCTAssertEqual(Journey.stopToCelebrate(celebrated: 27, reached: 31), 29)
    }

    func testChestOnSecondLapIsCelebrated() {
        // 29 — финиш первого круга, 34 — пятая остановка второго.
        XCTAssertEqual(Journey.stopToCelebrate(celebrated: 30, reached: 34), 34)
    }

    func testFallingBackIsNotCelebrated() {
        XCTAssertNil(Journey.stopToCelebrate(celebrated: 6, reached: 5))
    }

    func testStopByGlobalNumberWrapsLaps() {
        XCTAssertEqual(Journey.stop(reached: 0).kind, .start)
        XCTAssertEqual(Journey.stop(reached: 5).index, 5)
        XCTAssertEqual(Journey.stop(reached: 29).kind, .finish)
        XCTAssertEqual(Journey.stop(reached: 31).index, 2)
        XCTAssertEqual(Journey.stop(reached: 58).kind, .finish)
    }
}
