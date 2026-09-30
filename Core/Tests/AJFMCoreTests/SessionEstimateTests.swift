import XCTest
@testable import AJFMCore

final class SessionEstimateTests: XCTestCase {

    func testBeforeFirstAnswerUsesTheDefaultPace() {
        XCTAssertEqual(SessionEstimate.secondsPerCard(answered: 0, elapsed: 30), 8)
        XCTAssertEqual(SessionEstimate.secondsPerCard(answered: 3, elapsed: 0), 8)
    }

    func testPaceComesFromAnsweredCards() {
        XCTAssertEqual(SessionEstimate.secondsPerCard(answered: 10, elapsed: 50), 5)
    }

    func testLongBreakDoesNotBlowUpThePace() {
        XCTAssertEqual(SessionEstimate.secondsPerCard(answered: 1, elapsed: 900), 120)
    }

    func testMinutesRoundUp() {
        XCTAssertEqual(SessionEstimate.minutesLeft(remaining: 10, secondsPerCard: 8), 2)  // 80 с
        XCTAssertEqual(SessionEstimate.minutesLeft(remaining: 1, secondsPerCard: 5), 1)
    }

    func testNothingLeftIsZeroMinutes() {
        XCTAssertEqual(SessionEstimate.minutesLeft(remaining: 0, secondsPerCard: 8), 0)
        XCTAssertEqual(SessionEstimate.minutesLeft(remaining: -2, secondsPerCard: 8), 0)
    }

    func testZeroPaceStillGivesAMinute() {
        XCTAssertEqual(SessionEstimate.minutesLeft(remaining: 3, secondsPerCard: 0), 1)
    }
}
