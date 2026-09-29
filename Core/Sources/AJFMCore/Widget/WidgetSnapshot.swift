import Foundation

/// Что приложение оставляет виджету: виджет не открывает базу, а читает
/// этот снимок из общей группы приложений.
///
/// Снимок устаревает с переходом учебного дня: вчерашнее «0 карточек»
/// сегодня уже неправда. Поэтому виджет показывает число, только пока день
/// тот же, а после — «загляни», не выдумывая цифр.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var dueCards: Int
    public var streakDays: Int
    public var studiedToday: Bool
    /// Доля цели дня, 0…1.
    public var goalFraction: Double
    /// Начало учебного дня, в который снимок сделан.
    public var studyDay: Date
    public var cutoffHour: Int
    /// Язык интерфейса: виджет живёт в своём процессе и настроек приложения не видит.
    public var language: String

    public init(dueCards: Int, streakDays: Int, studiedToday: Bool, goalFraction: Double,
                studyDay: Date, cutoffHour: Int, language: String) {
        self.dueCards = max(dueCards, 0)
        self.streakDays = max(streakDays, 0)
        self.studiedToday = studiedToday
        self.goalFraction = min(max(goalFraction.isFinite ? goalFraction : 0, 0), 1)
        self.studyDay = studyDay
        self.cutoffHour = cutoffHour
        self.language = language
    }

    public static let defaultsKey = "widget.snapshot"

    /// Что показать сейчас.
    public enum Presentation: Equatable, Sendable {
        /// Снимка нет: приложение ещё не открывали или группа не настроена.
        case empty
        /// Снимок сегодняшний — цифрам можно верить.
        case today(due: Int, streak: Int, studied: Bool, goal: Double)
        /// Наступил новый учебный день: карточки уже подошли, но сколько —
        /// неизвестно. Серия под угрозой, если вчера не занимались.
        case newDay(streak: Int, streakAtRisk: Bool)
    }

    public static func presentation(of snapshot: WidgetSnapshot?, now: Date,
                                    calendar: Calendar = .current) -> Presentation {
        guard let snapshot else { return .empty }
        let today = ReviewQueueBuilder.studyDayStart(for: now, cutoffHour: snapshot.cutoffHour,
                                                     calendar: calendar)
        if today <= snapshot.studyDay {
            return .today(due: snapshot.dueCards, streak: snapshot.streakDays,
                          studied: snapshot.studiedToday, goal: snapshot.goalFraction)
        }
        // Снимок вчерашний: серия ещё жива (вчера её держали занятия или
        // заморозка) и её можно продолжить сегодня. Старше — виджет не знает,
        // что стало с заморозками, и серию не обещает.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        guard snapshot.studyDay >= yesterday else { return .newDay(streak: 0, streakAtRisk: false) }
        return .newDay(streak: snapshot.streakDays, streakAtRisk: snapshot.streakDays > 0)
    }

    /// Когда виджету перерисоваться: в начале следующего учебного дня.
    public static func nextRefresh(after now: Date, cutoffHour: Int,
                                   calendar: Calendar = .current) -> Date {
        let today = ReviewQueueBuilder.studyDayStart(for: now, cutoffHour: cutoffHour, calendar: calendar)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(self)
    }

    /// Битый или чужой снимок — как будто его нет: виджет не должен падать.
    public static func decode(_ data: Data?) -> WidgetSnapshot? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
