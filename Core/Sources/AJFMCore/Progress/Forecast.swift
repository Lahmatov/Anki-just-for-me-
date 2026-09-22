import Foundation

public struct ForecastDay: Equatable, Sendable, Identifiable {
    public var date: Date
    public var dueCount: Int
    public var id: Date { date }
}

public struct ProgressPoint: Equatable, Sendable, Identifiable {
    public var date: Date
    public var matureWords: Int
    public var id: Date { date }
}

/// Прогноз нагрузки и кривая роста.
///
/// Прогноз отвечает на единственный вопрос, который реально волнует: не свалится
/// ли завтра триста карточек. Видя горб заранее, можно сбавить приток новых.
public enum Forecast {

    /// Сколько карточек придёт по дням вперёд.
    public static func upcoming(
        dueDates: [Date], days: Int = 30, from now: Date = Date(),
        cutoffHour: Int = 4, calendar: Calendar = .current
    ) -> [ForecastDay] {
        let start = ReviewQueueBuilder.studyDayStart(
            for: now, cutoffHour: cutoffHour, calendar: calendar)

        var buckets: [Date: Int] = [:]
        for offset in 0..<max(1, days) {
            buckets[start.addingTimeInterval(Double(offset) * 86_400)] = 0
        }

        for due in dueDates {
            let day = ReviewQueueBuilder.studyDayStart(
                for: due, cutoffHour: cutoffHour, calendar: calendar)
            // Просроченное сваливается в сегодня — оно и правда ждёт сегодня.
            let bucket = day < start ? start : day
            guard buckets[bucket] != nil else { continue }
            buckets[bucket, default: 0] += 1
        }

        return buckets
            .map { ForecastDay(date: $0.key, dueCount: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// День с самой большой нагрузкой — его и подписываем на графике,
    /// подписывать каждый столбик бессмысленно.
    public static func peak(_ days: [ForecastDay]) -> ForecastDay? {
        days.max { $0.dueCount < $1.dueCount }
    }

    public static func total(_ days: [ForecastDay]) -> Int {
        days.reduce(0) { $0 + $1.dueCount }
    }

    /// Средняя нагрузка в день — по ней видно, потянешь ли темп.
    public static func averagePerDay(_ days: [ForecastDay]) -> Double {
        days.isEmpty ? 0 : Double(total(days)) / Double(days.count)
    }

    /// Активность по неделям: сколько повторов сделано.
    public static func weeklyActivity(
        reviewDates: [Date], weeks: Int = 8, from now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ForecastDay] {
        guard weeks > 0 else { return [] }
        let startOfWeek = { (date: Date) -> Date in
            let weekday = calendar.component(.weekday, from: date)
            let daysFromMonday = (weekday + 5) % 7
            let midnight = calendar.startOfDay(for: date)
            return midnight.addingTimeInterval(-Double(daysFromMonday) * 86_400)
        }

        let currentWeek = startOfWeek(now)
        var buckets: [Date: Int] = [:]
        for offset in 0..<weeks {
            buckets[currentWeek.addingTimeInterval(-Double(offset) * 7 * 86_400)] = 0
        }

        for date in reviewDates {
            let week = startOfWeek(date)
            guard buckets[week] != nil else { continue }
            buckets[week, default: 0] += 1
        }

        return buckets
            .map { ForecastDay(date: $0.key, dueCount: $0.value) }
            .sorted { $0.date < $1.date }
    }
}
