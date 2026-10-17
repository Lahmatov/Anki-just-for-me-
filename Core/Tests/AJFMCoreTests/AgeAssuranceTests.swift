import XCTest
@testable import AJFMCore

final class AgeBracketTests: XCTestCase {
    // Границы запроса — 13, 16, 18; ответы — как их описывает DeclaredAgeRange.

    func testNoLowerBoundMeansYoungerThanTheLowestGate() {
        XCTAssertEqual(AgeAssurance.bracket(lowerBound: nil, upperBound: 13), .under13)
    }

    func testBoundsMapToTheTexasGroups() {
        XCTAssertEqual(AgeAssurance.bracket(lowerBound: 13, upperBound: 16), .from13to15)
        XCTAssertEqual(AgeAssurance.bracket(lowerBound: 16, upperBound: 18), .from16to17)
        XCTAssertEqual(AgeAssurance.bracket(lowerBound: 18, upperBound: nil), .adult)
    }

    func testWithoutUpperBoundTheLowerBoundDecides() {
        // Система заменила границы на свои (13, 16): «16+» — может быть и 17.
        XCTAssertEqual(AgeAssurance.bracket(lowerBound: 16, upperBound: nil), .from16to17)
    }

    func testRegionalGatesAboveOursStillCountAsAdult() {
        // Закон страны может поднять совершеннолетие: границы 18 и 21.
        XCTAssertEqual(AgeAssurance.bracket(lowerBound: 18, upperBound: 21), .adult)
    }

    func testLowerBoundBelowMinimumIsUnder13() {
        XCTAssertEqual(AgeAssurance.bracket(lowerBound: 9, upperBound: 13), .under13)
    }
}

final class AgeDecisionTests: XCTestCase {
    func testWithoutALegalRequirementAgeIsIgnored() {
        XCTAssertEqual(AgeAssurance.decision(required: false, bracket: .under13), .notRequired)
        XCTAssertEqual(AgeAssurance.decision(required: false, bracket: nil), .notRequired)
    }

    func testRequiredButNotSharedAsksAgain() {
        XCTAssertEqual(AgeAssurance.decision(required: true, bracket: nil), .needsAge)
        XCTAssertFalse(AgeAssurance.allowsAccess(.needsAge))
    }

    func testChildrenUnder13AreKeptOut() {
        XCTAssertEqual(AgeAssurance.decision(required: true, bracket: .under13), .underMinimumAge)
        XCTAssertFalse(AgeAssurance.allowsAccess(.underMinimumAge))
    }

    func testTeensUseTheAppWithoutAnalytics() {
        XCTAssertEqual(AgeAssurance.decision(required: true, bracket: .from13to15), .minor)
        XCTAssertEqual(AgeAssurance.decision(required: true, bracket: .from16to17), .minor)
        XCTAssertTrue(AgeAssurance.allowsAccess(.minor))
        XCTAssertFalse(AgeAssurance.allowsAnalytics(.minor))
    }

    func testAdultsAndUnregulatedRegionsKeepAnalyticsChoice() {
        XCTAssertTrue(AgeAssurance.allowsAnalytics(.adult))
        XCTAssertTrue(AgeAssurance.allowsAnalytics(.notRequired))
        XCTAssertTrue(AgeAssurance.allowsAnalytics(nil), "проверки ещё не было")
    }
}

final class AgeRecheckTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ count: Double) -> Date { start.addingTimeInterval(count * 86_400) }

    func testFirstLaunchChecks() {
        XCTAssertTrue(AgeAssurance.shouldCheck(last: nil, now: start))
    }

    func testAdultIsRecheckedMonthly() {
        let adult = AgeCheckRecord(decision: .adult, checkedAt: start)
        XCTAssertFalse(AgeAssurance.shouldCheck(last: adult, now: days(29)))
        XCTAssertTrue(AgeAssurance.shouldCheck(last: adult, now: days(30)))
    }

    func testTeensAndBlockedAreCheckedEveryLaunch() {
        for decision in [AgeDecision.minor, .underMinimumAge, .needsAge, .notRequired] {
            let record = AgeCheckRecord(decision: decision, checkedAt: start)
            XCTAssertTrue(AgeAssurance.shouldCheck(last: record, now: days(0.01)), decision.rawValue)
        }
    }

    func testRecordSurvivesARoundTrip() throws {
        let record = AgeCheckRecord(decision: .minor, checkedAt: start)
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(AgeCheckRecord.self, from: data), record)
    }

    func testUnknownDecisionInStorageFailsToDecode() {
        let data = Data(#"{"decision":"teen","checkedAt":0}"#.utf8)
        XCTAssertNil(try? JSONDecoder().decode(AgeCheckRecord.self, from: data))
    }
}

final class SignificantChangeTests: XCTestCase {
    private let lessons = SignificantChange(id: "lessons-ai", introducedIn: "1.2", summary: "")
    private let voice = SignificantChange(id: "voice-upload", introducedIn: "1.10", summary: "")

    func testNoSignificantChangesUntilTheParentalConsentFlowExists() {
        // Добавляешь изменение — сначала экран согласия родителя (P-75).
        XCTAssertTrue(SignificantChanges.all.isEmpty)
    }

    func testChangesAfterTheInstalledVersionArePending() {
        let pending = SignificantChanges.pending([lessons, voice], originalVersion: "1.0", handled: [])
        XCTAssertEqual(pending.map(\.id), ["lessons-ai", "voice-upload"])
    }

    func testChangesPresentAtInstallAreNotAsked() {
        let pending = SignificantChanges.pending([lessons, voice], originalVersion: "1.2", handled: [])
        XCTAssertEqual(pending.map(\.id), ["voice-upload"])
    }

    func testHandledChangesAreNotAskedAgain() {
        XCTAssertTrue(SignificantChanges.pending([lessons], originalVersion: "1.0",
                                                 handled: ["lessons-ai"]).isEmpty)
    }

    func testVersionsCompareNumerically() {
        XCTAssertEqual(SignificantChanges.compare("1.10", "1.9"), .orderedDescending)
        XCTAssertEqual(SignificantChanges.compare("1.0", "1"), .orderedSame)
        XCTAssertEqual(SignificantChanges.compare("2", "10"), .orderedAscending)
    }

    func testGarbageVersionCountsAsZero() {
        XCTAssertEqual(SignificantChanges.compare("beta", "0"), .orderedSame)
    }
}
