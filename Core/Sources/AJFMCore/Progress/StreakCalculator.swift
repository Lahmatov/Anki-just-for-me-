import Foundation

/// Серия учебных дней с учётом «заморозок».
public struct StreakStatus: Equatable, Sendable {
    /// Сколько дней подряд занимался. Замороженные дни цепочку не рвут,
    /// но и в счёт не идут — иначе серию можно было бы нарастить, не занимаясь.
    public var days: Int
    /// Пропущенные дни, которые прикрыла заморозка.
    public var frozenDays: [Date]
    /// Сколько заморозок осталось в текущем месяце.
    public var freezesLeft: Int
    /// Сегодня уже занимался — серия на сегодня в безопасности.
    public var studiedToday: Bool

    /// Серия есть, а сегодня ещё не занимался — самое время напомнить.
    public var isAtRisk: Bool { days > 0 && !studiedToday }

    public init(days: Int, frozenDays: [Date], freezesLeft: Int, studiedToday: Bool) {
        self.days = days
        self.frozenDays = frozenDays
        self.freezesLeft = freezesLeft
        self.studiedToday = studiedToday
    }
}

public struct WeekProgress: Equatable, Sendable {
    public var daysStudied: Int
    public var target: Int
    public var isReached: Bool { daysStudied >= target }
    public var fraction: Double {
        target <= 0 ? 1 : min(1, Double(daysStudied) / Double(target))
    }
}

/// Счёт учебных дней: серия подряд с заморозками и недельная цель.
///
/// Две мерки дополняют друг друга. Серия тянет вернуться завтра, а заморозка
/// снимает страх, что один пропуск обнулит всё. Недельная цель мягче —
/// она просто прощает пропущенный вторник.
public enum StreakCalculator {

    /// Учебные дни, к которым относятся повторы. Занятие в час ночи
    /// засчитывается во вчерашний день — см. `dayCutoffHour`.
    public static func studyDays(
        from reviewDates: [Date], cutoffHour: Int, calendar: Calendar = .current
    ) -> Set<Date> {
        Set(reviewDates.map {
            ReviewQueueBuilder.studyDayStart(
                for: $0, cutoffHour: cutoffHour, calendar: calendar)
        })
    }

    /// Сколько учебных дней подряд, считая от сегодняшнего.
    /// Если сегодня ещё не занимался, счёт не рвётся — день не кончился.
    public static func currentStreak(
        studyDays: Set<Date>, now: Date = Date(), cutoffHour: Int,
        calendar: Calendar = .current
    ) -> Int {
        let today = ReviewQueueBuilder.studyDayStart(
            for: now, cutoffHour: cutoffHour, calendar: calendar)

        // Сутки отсчитываем календарём, а не вычитанием 86 400 секунд:
        // в день перехода на летнее время их 23 или 25, и шаг в секундах
        // промахивается мимо учебного дня, рвя счёт на ровном месте.
        func previousDay(_ date: Date) -> Date {
            calendar.date(byAdding: .day, value: -1, to: date)
                ?? date.addingTimeInterval(-86_400)
        }

        var streak = 0
        var day = studyDays.contains(today) ? today : previousDay(today)

        while studyDays.contains(day) {
            streak += 1
            day = previousDay(day)
        }
        return streak
    }

    /// Серия с автоматическими заморозками.
    ///
    /// Раньше заморозки только считались и ничего не защищали. А это одна из
    /// самых проверенных механик удержания: у Duolingo заморозка сократила
    /// отток среди тех, кто рисковал потерять серию, на 21%. Она убирает
    /// катастрофу «один пропуск — и сто дней в ноль», из-за которой бросают
    /// приложение целиком, но не убирает ежедневного стимула вернуться.
    ///
    /// Считается проходом **вперёд** по дням — так, как это переживает сам
    /// человек. Прошёл день без занятий — заморозка тратится сразу, и это
    /// решение потом не пересматривается. Пересчёт назад от сегодняшнего дня
    /// перекладывал бы заморозки задним числом: пропуск, который вчера был
    /// показан как незащищённый, сегодня оказывался бы прикрыт, а после
    /// разрыва серии месячный лимит сбрасывался бы и позволял больше двух.
    ///
    /// Правила:
    /// - заморозка тратится, только если есть что защищать — серия больше нуля;
    /// - в месяц их не больше `freezesPerMonth`, и потраченные остаются
    ///   потраченными, даже если серия потом всё-таки прервалась;
    /// - подряд их тоже не больше `freezesPerMonth`: иначе дыра через границу
    ///   месяца прикрывалась бы вдвое длиннее обещанного;
    /// - замороженные дни цепочку не рвут, но в счёт не идут;
    /// - сегодняшний день ещё не кончился, поэтому пропуском не считается.
    public static func streakStatus(
        studyDays: Set<Date>, now: Date = Date(), cutoffHour: Int,
        freezesPerMonth: Int = 2, calendar: Calendar = .current
    ) -> StreakStatus {
        let today = ReviewQueueBuilder.studyDayStart(
            for: now, cutoffHour: cutoffHour, calendar: calendar)
        let studiedToday = studyDays.contains(today)
        let allowance = max(0, freezesPerMonth)

        func monthKey(_ date: Date) -> DateComponents {
            calendar.dateComponents([.year, .month], from: date)
        }
        func nextDay(_ date: Date) -> Date {
            calendar.date(byAdding: .day, value: 1, to: date)
                ?? date.addingTimeInterval(86_400)
        }

        guard let earliest = studyDays.min() else {
            return StreakStatus(
                days: 0, frozenDays: [], freezesLeft: allowance, studiedToday: false)
        }

        var usedPerMonth: [DateComponents: Int] = [:]
        var streak = 0
        var frozenInStreak: [Date] = []
        var consecutiveFrozen = 0

        var day = earliest
        while day < today {
            if studyDays.contains(day) {
                streak += 1
                consecutiveFrozen = 0
            } else {
                let key = monthKey(day)
                let canFreeze = streak > 0
                    && usedPerMonth[key, default: 0] < allowance
                    && consecutiveFrozen < allowance
                if canFreeze {
                    usedPerMonth[key, default: 0] += 1
                    consecutiveFrozen += 1
                    frozenInStreak.append(day)
                } else {
                    streak = 0
                    frozenInStreak = []
                    consecutiveFrozen = 0
                }
            }
            day = nextDay(day)
        }

        if studiedToday { streak += 1 }

        return StreakStatus(
            days: streak,
            frozenDays: frozenInStreak,
            freezesLeft: max(0, allowance - usedPerMonth[monthKey(today), default: 0]),
            studiedToday: studiedToday)
    }

    /// Прогресс текущей недели.
    public static func weekProgress(
        studyDays: Set<Date>, target: Int, now: Date = Date(), cutoffHour: Int,
        calendar: Calendar = .current
    ) -> WeekProgress {
        let today = ReviewQueueBuilder.studyDayStart(
            for: now, cutoffHour: cutoffHour, calendar: calendar)
        let weekday = calendar.component(.weekday, from: today)
        // Неделя считается от понедельника независимо от языка системы.
        let daysFromMonday = (weekday + 5) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: today)
            ?? today.addingTimeInterval(-Double(daysFromMonday) * 86_400)

        let studied = studyDays.filter { $0 >= weekStart && $0 <= today }.count
        return WeekProgress(daysStudied: studied, target: max(1, target))
    }
}
