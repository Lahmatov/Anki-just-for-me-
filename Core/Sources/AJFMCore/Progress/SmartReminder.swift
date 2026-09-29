import Foundation

/// Умное напоминание: не в фиксированное время, а тогда, когда человек
/// обычно садится заниматься, — и только в дни, когда он ещё не занимался.
///
/// Время учится по истории: берётся начало учёбы каждого учебного дня за
/// последние три недели и его медиана. Медиана, а не среднее: одна ночная
/// сессия в три часа не должна сдвигать напоминание на полночь.
public enum SmartReminder {
    /// Сколько учебных дней нужно, чтобы доверять истории.
    public static let minimumDays = 3
    /// Окно истории: привычки меняются, полугодовая давность не в счёт.
    public static let windowDays = 21
    /// Запас после обычного времени: напоминать ровно в момент, когда
    /// человек и так сел бы заниматься, — значит мешать, а не помогать.
    public static let graceMinutes = 15
    /// На сколько дней вперёд ставить. Каждый запуск и каждая сессия
    /// перестраивают план; кто не открывал приложение неделю, дальше
    /// не получает напоминаний — навязчивость хуже молчания.
    public static let daysAhead = 7

    /// Время суток в минутах от полуночи.
    public struct Time: Equatable, Sendable {
        public var hour: Int
        public var minute: Int

        public init(hour: Int, minute: Int) {
            self.hour = hour
            self.minute = minute
        }

        public init(minutes: Int) {
            let wrapped = ((minutes % 1440) + 1440) % 1440
            self.init(hour: wrapped / 60, minute: wrapped % 60)
        }

        public var minutes: Int { hour * 60 + minute }
    }

    /// Обычное время начала учёбы или nil, если истории мало.
    ///
    /// Минуты считаются от начала учебного дня (`cutoffHour`), а не от
    /// полуночи: у совы сессии в 23:50 и в 00:20 — это одна привычка, и
    /// медиана от полуночи развела бы их по разным концам суток.
    public static func usualStart(
        sessions: [Date], now: Date, cutoffHour: Int, calendar: Calendar = .current
    ) -> Time? {
        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        var firstByDay: [Date: Date] = [:]
        for session in sessions where session >= windowStart && session <= now {
            let day = ReviewQueueBuilder.studyDayStart(for: session, cutoffHour: cutoffHour,
                                                       calendar: calendar)
            if let known = firstByDay[day], known <= session { continue }
            firstByDay[day] = session
        }
        guard firstByDay.count >= minimumDays else { return nil }

        let offset = cutoffHour * 60
        let shifted = firstByDay.values.map { date -> Int in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            return ((minutes - offset) % 1440 + 1440) % 1440
        }.sorted()
        let middle = shifted.count / 2
        let median = shifted.count % 2 == 1
            ? shifted[middle] : (shifted[middle - 1] + shifted[middle]) / 2
        return Time(minutes: median + offset)
    }

    /// Во сколько напоминать: обычное время плюс запас, до пяти минут.
    public static func reminderTime(forUsual usual: Time) -> Time {
        let minutes = usual.minutes + graceMinutes
        return Time(minutes: (minutes + 4) / 5 * 5)
    }

    /// Когда напоминать в ближайшие дни. Сегодня — только если сегодня
    /// ещё не занимались и время не прошло; дальше — по одному в день.
    public static func schedule(
        at time: Time, now: Date, studiedToday: Bool, cutoffHour: Int,
        calendar: Calendar = .current, days: Int = daysAhead
    ) -> [Date] {
        guard days > 0 else { return [] }
        let today = ReviewQueueBuilder.studyDayStart(for: now, cutoffHour: cutoffHour, calendar: calendar)
        var result: [Date] = []
        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let date = moment(time, inStudyDay: day, cutoffHour: cutoffHour, calendar: calendar)
            else { continue }
            if offset == 0 && (studiedToday || date <= now) { continue }
            if date <= now { continue }
            result.append(date)
            if result.count == days { break }
        }
        return result
    }

    /// Момент времени внутри учебного дня: 00:30 при переходе дня в 4 утра —
    /// это уже следующая календарная дата.
    static func moment(_ time: Time, inStudyDay start: Date, cutoffHour: Int,
                       calendar: Calendar) -> Date? {
        guard let sameDate = calendar.date(bySettingHour: time.hour, minute: time.minute,
                                           second: 0, of: start) else { return nil }
        return time.hour < cutoffHour
            ? calendar.date(byAdding: .day, value: 1, to: sameDate) : sameDate
    }
}
