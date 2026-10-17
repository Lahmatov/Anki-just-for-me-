import XCTest
@testable import AJFMCore

final class ReviewPromptTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ count: Double) -> Date { start.addingTimeInterval(count * 86_400) }
    private var fresh: ReviewPromptState { ReviewPromptState(firstLaunch: start) }

    func testAsksAfterAGoodMomentForAnEngagedLearner() {
        XCTAssertTrue(ReviewPrompt.shouldAsk(now: days(10), state: fresh, appVersion: "1.0",
                                             studyDays: 6, moment: .perfectSession))
    }

    func testNeverWithoutAGoodMoment() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(now: days(10), state: fresh, appVersion: "1.0",
                                              studyDays: 30, moment: nil))
    }

    func testNotInTheFirstWeekOrForCasualUse() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(now: days(3), state: fresh, appVersion: "1.0",
                                              studyDays: 6, moment: .dailyGoal), "первая неделя")
        XCTAssertFalse(ReviewPrompt.shouldAsk(now: days(30), state: fresh, appVersion: "1.0",
                                              studyDays: 4, moment: .dailyGoal), "мало учебных дней")
    }

    func testOncePerVersionAndWithALongPause() {
        let asked = ReviewPrompt.asked(fresh, now: days(10), appVersion: "1.0")
        XCTAssertFalse(ReviewPrompt.shouldAsk(now: days(200), state: asked, appVersion: "1.0",
                                              studyDays: 50, moment: .quizPassed), "та же версия")
        XCTAssertFalse(ReviewPrompt.shouldAsk(now: days(60), state: asked, appVersion: "1.1",
                                              studyDays: 50, moment: .quizPassed), "рано после прошлой")
        XCTAssertTrue(ReviewPrompt.shouldAsk(now: days(140), state: asked, appVersion: "1.1",
                                             studyDays: 50, moment: .quizPassed))
    }

    func testAskingRemembersTheVersionOnce() {
        let twice = ReviewPrompt.asked(ReviewPrompt.asked(fresh, now: days(10), appVersion: "1.0"),
                                       now: days(11), appVersion: "1.0")
        XCTAssertEqual(twice.askedVersions, ["1.0"])
        XCTAssertEqual(twice.lastAsked, days(11))
    }
}

final class AnalyticsEventTests: XCTestCase {
    func testNothingLeavesWithoutConsent() {
        XCTAssertNil(AnalyticsGate(consent: false).payload(.quizFinished(passed: true)))
        XCTAssertEqual(AnalyticsGate(consent: true).payload(.quizFinished(passed: true))?.name, "quiz_finished")
    }

    /// Числа — только корзинами: точное число карточек и процент не уходят.
    func testNumbersAreBucketed() {
        let properties = AnalyticsEvent.sessionFinished(cards: 23, accuracy: 0.876).properties
        XCTAssertEqual(properties, ["cards": "11-25", "accuracy": "80"])
        XCTAssertEqual(AnalyticsEvent.bucket(0), "0")
        XCTAssertEqual(AnalyticsEvent.bucket(500), "50+")
        XCTAssertEqual(AnalyticsEvent.percentBucket(1.5), "100")
        XCTAssertEqual(AnalyticsEvent.percentBucket(-1), "0")
        XCTAssertEqual(AnalyticsEvent.percentBucket(.nan), "0")
    }

    /// Свободный текст в событие не попадает: незнакомый режим — «other».
    func testFreeTextNeverBecomesAProperty() {
        XCTAssertEqual(AnalyticsEvent.drillFinished(mode: "my secret word", score: 0.5).properties["mode"], "other")
        XCTAssertEqual(AnalyticsEvent.drillFinished(mode: "dictation", score: 0.5).properties["mode"], "dictation")
    }

    func testEveryEventHasASnakeCaseName() {
        let events: [AnalyticsEvent] = [
            .sessionFinished(cards: 1, accuracy: 1), .lessonCreated(source: .photo),
            .drillFinished(mode: "cloze", score: 1), .quizFinished(passed: false),
            .studyLanguageSwitched(to: .italian), .supportSent(category: .bug), .reviewPrompted,
        ]
        for event in events {
            XCTAssertNotNil(event.name.range(of: "^[a-z_]+$", options: .regularExpression), event.name)
            for value in event.properties.values { XCTAssertLessThanOrEqual(value.count, 12, event.name) }
        }
    }
}

final class CrashLogTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ kind: CrashRecord.Kind, daysAgo: Double, reason: String = "SIGSEGV") -> CrashRecord {
        CrashRecord(kind: kind, date: now.addingTimeInterval(-daysAgo * 86_400), reason: reason, appVersion: "0.4 (17)")
    }

    func testOldRecordsAreDropped() {
        let merged = CrashLog.merge([record(.crash, daysAgo: 40)], adding: [record(.hang, daysAgo: 1)], now: now)
        XCTAssertEqual(merged.map(\.kind), [.hang])
    }

    func testOnlyTheNewestAreKept() {
        let many = (0..<80).map { record(.crash, daysAgo: Double($0) / 10) }
        let merged = CrashLog.merge([], adding: many, now: now)
        XCTAssertEqual(merged.count, CrashLog.limit)
        XCTAssertEqual(merged.last?.date, now)
    }

    func testSummaryCountsKindsAndNamesTheLastCrash() {
        let summary = CrashLog.summary([record(.crash, daysAgo: 3, reason: "EXC_BAD_ACCESS"),
                                        record(.hang, daysAgo: 2), record(.crash, daysAgo: 1)])
        XCTAssertEqual(summary, ["crashes": "2", "hangs": "1", "lastCrash": "SIGSEGV 0.4 (17)"])
        XCTAssertEqual(CrashLog.summary([]), [:])
    }

    /// Ключи сводки — только буквы: сервер поддержки другие не примет.
    func testSummaryKeysFitSupportDiagnostics() {
        let summary = CrashLog.summary([record(.crash, daysAgo: 1)])
        for key in summary.keys {
            XCTAssertNotNil(key.range(of: "^[a-zA-Z]{1,32}$", options: .regularExpression))
        }
        let long = CrashRecord(kind: .crash, date: now, reason: String(repeating: "x", count: 200), appVersion: "1")
        XCTAssertEqual(long.reason.count, 40, "без адресов и длинных описаний")
    }
}

final class CrashReasonTests: XCTestCase {
    func testKnownSignalsAndExceptionsHaveNames() {
        XCTAssertEqual(CrashLog.reason(signal: 11, exceptionType: nil), "SIGSEGV")
        XCTAssertEqual(CrashLog.reason(signal: 11, exceptionType: 1), "EXC_BAD_ACCESS", "исключение точнее сигнала")
        XCTAssertEqual(CrashLog.reason(signal: 42, exceptionType: nil), "signal 42")
        XCTAssertEqual(CrashLog.reason(signal: nil, exceptionType: nil), "unknown")
    }
}
