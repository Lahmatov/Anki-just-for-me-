import Foundation

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
