import XCTest
@testable import AJFMCore

final class StreakWithFreezesTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func days(_ dates: [Date]) -> Set<Date> {
        StreakCalculator.studyDays(from: dates, cutoffHour: 4, calendar: calendar)
    }

    private func status(
        _ studied: [Date], now: Date, freezes: Int = 2
    ) -> StreakStatus {
        StreakCalculator.streakStatus(
            studyDays: days(studied), now: now, cutoffHour: 4,
            freezesPerMonth: freezes, calendar: calendar)
    }

    func testUnbrokenChainNeedsNoFreezes() {
        let result = status([date(3, 9), date(3, 10), date(3, 11)], now: date(3, 11, 20))
        XCTAssertEqual(result.days, 3)
        XCTAssertTrue(result.frozenDays.isEmpty)
        XCTAssertEqual(result.freezesLeft, 2)
        XCTAssertTrue(result.studiedToday)
    }

    func testSingleMissedDayIsBridged() {
        // Раньше заморозки только считались и ничего не защищали:
        // один пропуск обнулял всю серию.
        let result = status([date(3, 8), date(3, 9), date(3, 11)], now: date(3, 11, 20))
        XCTAssertEqual(result.days, 3, "пропущенный 10-й прикрыт и в счёт не идёт")
        XCTAssertEqual(result.frozenDays, [date(3, 10, 4)])
        XCTAssertEqual(result.freezesLeft, 1)
    }

    func testFrozenDaysDoNotInflateTheCount() {
        // Иначе серию можно было бы нарастить, не занимаясь вовсе.
        let result = status([date(3, 5), date(3, 7)], now: date(3, 7, 20))
        XCTAssertEqual(result.days, 2)
        XCTAssertEqual(result.frozenDays.count, 1)
    }

    func testGapLongerThanAllowanceBreaksTheStreak() {
        let result = status([date(3, 5), date(3, 9)], now: date(3, 9, 20))
        // Три пропуска подряд, а заморозок две — дыру не закрыть.
        XCTAssertEqual(result.days, 1)
        XCTAssertTrue(result.frozenDays.isEmpty, "от прерванной серии заморозок не остаётся")
        // Первые два дня заморозки честно прикрывали — в тот момент никто
        // не знал, что пропуск затянется. Задним числом они не возвращаются.
        XCTAssertEqual(result.freezesLeft, 0)
    }

    func testBrokenStreakDoesNotRefillTheMonthlyAllowance() {
        // 3 и 4 марта прикрыты, 6-го заморозок уже нет — серия рвётся.
        // Пересчёт назад от сегодняшнего дня «нашёл» бы для 6-го свежую
        // заморозку и выдал три прикрытых дня за месяц вместо двух.
        let result = status([date(3, 1), date(3, 2), date(3, 5), date(3, 7)], now: date(3, 7, 20))
        XCTAssertEqual(result.days, 1)
        XCTAssertTrue(result.frozenDays.isEmpty)
        XCTAssertEqual(result.freezesLeft, 0)
    }

    func testFrozenDaysStayFrozenWhenViewedLater() {
        // Решение о заморозке принимается один раз и потом не пересматривается.
        let before = status([date(3, 8), date(3, 10)], now: date(3, 10, 20))
        let after = status(
            [date(3, 8), date(3, 10), date(3, 11), date(3, 12)], now: date(3, 12, 20))
        XCTAssertEqual(before.frozenDays, [date(3, 9, 4)])
        XCTAssertEqual(after.frozenDays, before.frozenDays)
        XCTAssertEqual(after.days, 4)
        XCTAssertEqual(after.freezesLeft, 1)
    }

    func testMonthBoundaryDoesNotDoubleTheGap() {
        // Пропуски 28 февраля, 1 и 2 марта. По месячному лимиту хватило бы
        // и февральских, и мартовских, но подряд больше двух не прикрываем —
        // иначе через границу месяца проходила бы дыра в четыре дня.
        let result = status([date(2, 26), date(2, 27), date(3, 3)], now: date(3, 3, 20))
        XCTAssertEqual(result.days, 1)
        XCTAssertTrue(result.frozenDays.isEmpty)
        XCTAssertEqual(result.freezesLeft, 1, "1 марта заморозка всё же потрачена")
    }

    func testTwoDayGapUsesBothFreezes() {
        let result = status([date(3, 6), date(3, 9)], now: date(3, 9, 20))
        XCTAssertEqual(result.days, 2)
        XCTAssertEqual(result.frozenDays.count, 2)
        XCTAssertEqual(result.freezesLeft, 0)
    }

    func testAllowanceIsPerMonth() {
        // Лимит считается по месяцам: февральская заморозка не съедает мартовскую.
        // Пропуски — 27 февраля и 1 марта, по одному на месяц.
        let studied = [date(2, 26), date(2, 28), date(3, 2), date(3, 3)]
        let result = StreakCalculator.streakStatus(
            studyDays: days(studied), now: date(3, 3, 20), cutoffHour: 4,
            freezesPerMonth: 1, calendar: calendar)
        XCTAssertEqual(result.days, 4)
        XCTAssertEqual(result.frozenDays.count, 2, "по одной в каждом месяце")
        XCTAssertEqual(result.freezesLeft, 0, "мартовская потрачена")
    }

    func testFreezesAreNotSpentBeforeTheFirstStudyDay() {
        // Дни до самого первого занятия — не разрыв, а начало серии.
        let result = status([date(3, 10)], now: date(3, 10, 20))
        XCTAssertEqual(result.days, 1)
        XCTAssertTrue(result.frozenDays.isEmpty)
        XCTAssertEqual(result.freezesLeft, 2)
    }

    func testTodayNotStudiedYetIsNotAMiss() {
        let result = status([date(3, 9), date(3, 10)], now: date(3, 11, 9))
        XCTAssertEqual(result.days, 2)
        XCTAssertTrue(result.frozenDays.isEmpty, "день не кончился — морозить нечего")
        XCTAssertFalse(result.studiedToday)
        XCTAssertTrue(result.isAtRisk, "самое время напомнить")
    }

    func testMissedYesterdayIsFrozenAutomatically() {
        let result = status([date(3, 8), date(3, 9)], now: date(3, 11, 9))
        XCTAssertEqual(result.days, 2)
        XCTAssertEqual(result.frozenDays, [date(3, 10, 4)])
    }

    func testZeroAllowanceBehavesLikePlainStreak() {
        let studied = [date(3, 8), date(3, 9), date(3, 11)]
        let withFreezes = status(studied, now: date(3, 11, 20), freezes: 0)
        let plain = StreakCalculator.currentStreak(
            studyDays: days(studied), now: date(3, 11, 20), cutoffHour: 4, calendar: calendar)
        XCTAssertEqual(withFreezes.days, plain)
        XCTAssertEqual(withFreezes.days, 1)
    }

    func testEmptyHistory() {
        let result = status([], now: date(3, 10))
        XCTAssertEqual(result.days, 0)
        XCTAssertFalse(result.isAtRisk, "нечего терять — нечем и пугать")
        XCTAssertEqual(result.freezesLeft, 2)
    }

    func testNegativeAllowanceIsTreatedAsZero() {
        let result = status([date(3, 8), date(3, 10)], now: date(3, 10, 20), freezes: -3)
        XCTAssertEqual(result.days, 1)
        XCTAssertEqual(result.freezesLeft, 0)
    }
}

final class LaunchAnimationPolicyTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    private func style(reduceMotion: Bool = false, last: Date?, now: Date)
        -> LaunchAnimationStyle {
        LaunchAnimationPolicy.style(
            reduceMotion: reduceMotion, lastFullShown: last, now: now,
            cutoffHour: 4, calendar: calendar)
    }

    func testFirstEverLaunchGetsTheFullAnimation() {
        XCTAssertEqual(style(last: nil, now: date(10, 9)), .full)
    }

    func testSecondLaunchTheSameDayIsBrief() {
        // Приложение открывают по нескольку раз в день; секунда анимации
        // на каждый раз превращается в трение.
        XCTAssertEqual(style(last: date(10, 9), now: date(10, 18)), .brief)
    }

    func testNewStudyDayBringsTheFullAnimationBack() {
        XCTAssertEqual(style(last: date(10, 22), now: date(11, 9)), .full)
    }

    func testLateNightStillCountsAsTheSameDay() {
        // В два часа ночи — всё ещё вчерашний учебный день.
        XCTAssertEqual(style(last: date(10, 21), now: date(11, 2)), .brief)
    }

    func testReduceMotionDisablesAnimationEntirely() {
        XCTAssertEqual(style(reduceMotion: true, last: nil, now: date(10, 9)), .none)
        XCTAssertEqual(style(reduceMotion: true, last: date(1, 9), now: date(10, 9)), .none)
    }

    func testDurationsStayWellUnderTheLimit() {
        // Три секунды — предел для таких экранов; нам нужно заметно меньше,
        // иначе запуск перестаёт ощущаться мгновенным.
        XCTAssertLessThan(LaunchAnimationStyle.full.duration, 2)
        XCTAssertLessThan(LaunchAnimationStyle.brief.duration, LaunchAnimationStyle.full.duration)
        XCTAssertEqual(LaunchAnimationStyle.none.duration, 0)
    }
}
