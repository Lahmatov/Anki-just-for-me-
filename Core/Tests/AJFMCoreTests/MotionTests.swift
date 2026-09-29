import XCTest
@testable import AJFMCore

final class ConfettiTests: XCTestCase {

    func testSameSeedGivesTheSameBurst() {
        XCTAssertEqual(Confetti.burst(count: 40, seed: 7), Confetti.burst(count: 40, seed: 7))
    }

    func testDifferentSeedsGiveDifferentBursts() {
        XCTAssertNotEqual(Confetti.burst(count: 40, seed: 7), Confetti.burst(count: 40, seed: 8))
    }

    func testBurstHasRequestedCount() {
        XCTAssertEqual(Confetti.burst(count: 60, seed: 1).count, 60)
    }

    func testZeroOrNegativeCountGivesNothing() {
        XCTAssertTrue(Confetti.burst(count: 0, seed: 1).isEmpty)
        XCTAssertTrue(Confetti.burst(count: -5, seed: 1).isEmpty)
    }

    func testEveryParticleStartsAtTheOriginAndFliesUp() {
        for particle in Confetti.burst(count: 200, seed: 42, origin: (0.3, 0.6)) {
            XCTAssertEqual(particle.x, 0.3)
            XCTAssertEqual(particle.y, 0.6)
            XCTAssertLessThan(particle.vy, 0, "веер вверх: скорость по y отрицательная")
        }
    }

    func testColorIndexStaysWithinPalette() {
        for particle in Confetti.burst(count: 300, seed: 3, colors: 4) {
            XCTAssertTrue((0..<4).contains(particle.colorIndex))
        }
    }

    func testSingleColorPaletteDoesNotCrash() {
        XCTAssertTrue(Confetti.burst(count: 10, seed: 3, colors: 0).allSatisfy { $0.colorIndex == 0 })
    }

    func testPositionAtStartIsTheOrigin() {
        let particle = Confetti.burst(count: 1, seed: 9)[0]
        let start = Confetti.position(of: particle, at: 0)
        XCTAssertEqual(start.x, particle.x, accuracy: 1e-12)
        XCTAssertEqual(start.y, particle.y, accuracy: 1e-12)
    }

    func testNegativeTimeIsTreatedAsStart() {
        let particle = Confetti.burst(count: 1, seed: 9)[0]
        XCTAssertEqual(Confetti.position(of: particle, at: -1).y, particle.y, accuracy: 1e-12)
    }

    func testParticleRisesFirstThenGravityPullsItDown() {
        let particle = Confetti.Particle(x: 0.5, y: 0.5, vx: 0, vy: -1, spin: 0, colorIndex: 0,
                                         size: 8, isRound: false)
        let early = Confetti.position(of: particle, at: 0.2).y
        let late = Confetti.position(of: particle, at: Confetti.lifetime).y
        XCTAssertLessThan(early, 0.5, "сначала вверх")
        XCTAssertGreaterThan(late, early, "потом вниз")
    }

    func testDragSlowsHorizontalDrift() {
        // Без сопротивления за 2 с ушло бы на 2 экрана; с ним — меньше.
        let particle = Confetti.Particle(x: 0, y: 0, vx: 1, vy: 0, spin: 0, colorIndex: 0,
                                         size: 8, isRound: false)
        XCTAssertLessThan(Confetti.position(of: particle, at: 2).x, 2)
        XCTAssertGreaterThan(Confetti.position(of: particle, at: 2).x, 0)
    }

    func testOpacityIsFullThenFadesToZero() {
        XCTAssertEqual(Confetti.opacity(at: 0), 1)
        XCTAssertEqual(Confetti.opacity(at: Confetti.lifetime / 2), 1)
        XCTAssertLessThan(Confetti.opacity(at: Confetti.lifetime * 0.9), 1)
        XCTAssertEqual(Confetti.opacity(at: Confetti.lifetime), 0)
        XCTAssertEqual(Confetti.opacity(at: Confetti.lifetime * 3), 0)
        XCTAssertEqual(Confetti.opacity(at: -1), 0)
    }

    func testOpacityNeverIncreases() {
        var previous = 1.0
        for step in 0...100 {
            let value = Confetti.opacity(at: Confetti.lifetime * Double(step) / 100)
            XCTAssertLessThanOrEqual(value, previous + 1e-12)
            previous = value
        }
    }

    func testFinishedOnlyAfterLifetime() {
        XCTAssertFalse(Confetti.isFinished(at: Confetti.lifetime - 0.01))
        XCTAssertTrue(Confetti.isFinished(at: Confetti.lifetime))
    }

    func testRandomUnitStaysInRange() {
        var random = SplitMix64(seed: 123)
        for _ in 0..<10_000 {
            let value = random.nextUnit()
            XCTAssertTrue(value >= 0 && value < 1)
        }
    }

    func testSplitMixMatchesReferenceVector() {
        // Эталон SplitMix64 для зерна 0 (Vigna, prng.di.unimi.it).
        var random = SplitMix64(seed: 0)
        XCTAssertEqual(random.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(random.next(), 0x6E78_9E6A_A1B9_65F4)
    }
}

final class ShakeTests: XCTestCase {

    func testShakeStartsAndEndsAtRest() {
        XCTAssertEqual(Shake.offset(progress: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(Shake.offset(progress: 1), 0, accuracy: 1e-9)
    }

    func testShakeNeverExceedsAmplitude() {
        for step in 0...200 {
            XCTAssertLessThanOrEqual(abs(Shake.offset(progress: Double(step) / 200, amplitude: 12)), 12)
        }
    }

    func testShakeActuallyMovesBothWays() {
        let values = (0...100).map { Shake.offset(progress: Double($0) / 100) }
        XCTAssertGreaterThan(values.max() ?? 0, 1)
        XCTAssertLessThan(values.min() ?? 0, -1)
    }

    func testProgressOutsideRangeIsClamped() {
        XCTAssertEqual(Shake.offset(progress: -3), 0, accuracy: 1e-9)
        XCTAssertEqual(Shake.offset(progress: 5), 0, accuracy: 1e-9)
    }
}

final class CelebrationTests: XCTestCase {

    func testGoalCelebratedWhenCrossedForTheFirstTimeToday() {
        XCTAssertTrue(Celebration.goalReached(progressBefore: 0.9, progressAfter: 1.0,
                                              celebratedDay: "2026-09-29", day: "2026-09-30"))
    }

    func testGoalNotCelebratedTwiceADay() {
        XCTAssertFalse(Celebration.goalReached(progressBefore: 0.9, progressAfter: 1.2,
                                               celebratedDay: "2026-09-30", day: "2026-09-30"))
    }

    func testGoalNotCelebratedWhenAlreadyDoneBefore() {
        // Открыл экран, когда цель давно выполнена, — не праздник.
        XCTAssertFalse(Celebration.goalReached(progressBefore: 1.3, progressAfter: 1.5,
                                               celebratedDay: nil, day: "2026-09-30"))
    }

    func testGoalNotCelebratedWhenNotReached() {
        XCTAssertFalse(Celebration.goalReached(progressBefore: 0.2, progressAfter: 0.99,
                                               celebratedDay: nil, day: "2026-09-30"))
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    func testDayKeyIsZeroPadded() {
        XCTAssertEqual(Celebration.dayKey(cutoffHour: 0, now: date("2026-03-05T12:00:00Z"), calendar: utc),
                       "2026-03-05")
    }

    func testLateNightCountsAsPreviousDay() {
        XCTAssertEqual(Celebration.dayKey(cutoffHour: 4, now: date("2026-09-30T01:30:00Z"), calendar: utc),
                       "2026-09-29")
    }

    func testAfterCutoffIsTheNewDay() {
        XCTAssertEqual(Celebration.dayKey(cutoffHour: 4, now: date("2026-09-30T04:00:00Z"), calendar: utc),
                       "2026-09-30")
    }

    func testNegativeCutoffIsTreatedAsMidnight() {
        XCTAssertEqual(Celebration.dayKey(cutoffHour: -3, now: date("2026-09-30T00:30:00Z"), calendar: utc),
                       "2026-09-30")
    }

    func testStreakMilestoneWhenCrossed() {
        XCTAssertEqual(Celebration.streakMilestone(previous: 6, current: 7), 7)
        XCTAssertEqual(Celebration.streakMilestone(previous: 29, current: 30), 30)
    }

    func testNoMilestoneBetweenMarks() {
        XCTAssertNil(Celebration.streakMilestone(previous: 7, current: 8))
    }

    func testNoMilestoneWhenStreakDidNotGrow() {
        XCTAssertNil(Celebration.streakMilestone(previous: 7, current: 7))
        XCTAssertNil(Celebration.streakMilestone(previous: 30, current: 0))
    }

    func testJumpOverSeveralMarksCelebratesTheHighest() {
        // После восстановления из бэкапа серия может прыгнуть сразу на много дней.
        XCTAssertEqual(Celebration.streakMilestone(previous: 2, current: 31), 30)
    }

    func testPerfectSessionIsBig() {
        XCTAssertEqual(Celebration.session(answered: 20, accuracy: 1), .big)
    }

    func testGoodSessionIsGood() {
        XCTAssertEqual(Celebration.session(answered: 20, accuracy: 0.8), .good)
    }

    func testTinyPerfectSessionIsOnlyGood() {
        XCTAssertEqual(Celebration.session(answered: 2, accuracy: 1), .good)
    }

    func testPoorOrEmptySessionIsNothing() {
        XCTAssertEqual(Celebration.session(answered: 20, accuracy: 0.5), .none)
        XCTAssertEqual(Celebration.session(answered: 0, accuracy: 0), .none)
        XCTAssertEqual(Celebration.session(answered: 10, accuracy: .nan), .none)
    }
}
