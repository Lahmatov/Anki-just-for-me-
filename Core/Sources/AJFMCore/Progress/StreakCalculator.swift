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

/// Счёт учебных дней.
///
/// Намеренно мягкая механика: цель недельная, а не ежедневная. Полоска
/// «дней подряд» отлично мотивирует ровно до первого пропуска, после
/// которого её обычно бросают вместе с приложением. Недельная цель
/// переживает пропущенный вторник.
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
    /// Пропущенный день прикрывается сам, если в его месяце остались заморозки.
    /// Прикрывается только разрыв внутри серии: тратить заморозки на дни до
    /// самого первого занятия незачем.
    public static func streakStatus(
        studyDays: Set<Date>, now: Date = Date(), cutoffHour: Int,
        freezesPerMonth: Int = 2, calendar: Calendar = .current
    ) -> StreakStatus {
        let today = ReviewQueueBuilder.studyDayStart(
            for: now, cutoffHour: cutoffHour, calendar: calendar)
        let studiedToday = studyDays.contains(today)
        let allowance = max(0, freezesPerMonth)

        func previousDay(_ date: Date) -> Date {
            calendar.date(byAdding: .day, value: -1, to: date)
                ?? date.addingTimeInterval(-86_400)
        }
        func monthKey(_ date: Date) -> DateComponents {
            calendar.dateComponents([.year, .month], from: date)
        }

        var usedPerMonth: [DateComponents: Int] = [:]
        var frozen: [Date] = []
        var days = 0
        let earliest = studyDays.min()

        // Сегодняшний день ещё не кончился: если занятия не было, это не пропуск.
        var day = studiedToday ? today : previousDay(today)

        while let earliest, day >= earliest {
            if studyDays.contains(day) {
                days += 1
                day = previousDay(day)
                continue
            }

            // Пропуск. Пробуем закрыть всю дыру заморозками — но только если
            // за ней снова есть занятия, иначе это не разрыв, а начало серии.
            var gap: [Date] = []
            var cursor = day
            var tentative = usedPerMonth
            while !studyDays.contains(cursor), cursor >= earliest {
                let key = monthKey(cursor)
                guard tentative[key, default: 0] < allowance else { break }
                tentative[key, default: 0] += 1
                gap.append(cursor)
                cursor = previousDay(cursor)
            }

            guard studyDays.contains(cursor), !gap.isEmpty else { break }
            usedPerMonth = tentative
            frozen.append(contentsOf: gap)
            day = cursor
        }

        let usedThisMonth = usedPerMonth[monthKey(today), default: 0]
        return StreakStatus(
            days: days,
            frozenDays: frozen,
            freezesLeft: max(0, allowance - usedThisMonth),
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

    /// Сколько «заморозок» осталось в этом месяце.
    ///
    /// Заморозка прикрывает один пропущенный день. Механика нужна не для
    /// поблажек, а чтобы одна командировка не обнуляла месяц усилий.
    public static func freezesLeft(
        usedDates: [Date], allowancePerMonth: Int, now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let usedThisMonth = usedDates.filter {
            calendar.isDate($0, equalTo: now, toGranularity: .month)
        }.count
        return max(0, allowancePerMonth - usedThisMonth)
    }
}
