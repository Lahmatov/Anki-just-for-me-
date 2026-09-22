import Foundation

/// Алгоритм интервальных повторений.
///
/// Реализации взаимозаменяемы и выбираются на уровне набора: за сериалы можно
/// взять FSRS, за срочную лексику к поездке — зубрёжку.
public protocol Scheduler: Sendable {
    var id: SchedulerID { get }

    /// Новое состояние карточки после выставленной оценки.
    func review(_ state: ReviewState, grade: Grade, now: Date) -> ReviewState

    /// Что будет, если нажать каждую из кнопок. Показывается прямо на кнопках,
    /// чтобы выбор оценки был осознанным.
    func preview(_ state: ReviewState, now: Date) -> [Grade: TimeInterval]
}

extension Scheduler {
    public func preview(_ state: ReviewState, now: Date) -> [Grade: TimeInterval] {
        var result: [Grade: TimeInterval] = [:]
        for grade in Grade.allCases {
            let next = review(state, grade: grade, now: now)
            result[grade] = max(0, next.due.timeIntervalSince(now))
        }
        return result
    }
}

public enum SchedulerFactory {
    public static func make(_ id: SchedulerID) -> any Scheduler {
        switch id {
        case .fsrs6: return FSRS6Scheduler()
        case .sm2: return SM2Scheduler()
        case .leitner: return LeitnerScheduler()
        case .cram: return CramScheduler()
        }
    }
}

/// Человекочитаемая длительность: «10 мин», «3 дня», «2.5 мес».
public enum IntervalFormatter {
    public static func short(_ interval: TimeInterval) -> String {
        let minutes = interval / 60
        if minutes < 1 { return "<1 мин" }
        if minutes < 60 { return "\(Int(minutes.rounded())) мин" }

        let hours = minutes / 60
        if hours < 24 { return "\(Int(hours.rounded())) ч" }

        let days = hours / 24
        if days < 30 { return "\(Int(days.rounded())) дн" }

        let months = days / 30.44
        if months < 12 {
            return months < 10
                ? String(format: "%.1f мес", months)
                : "\(Int(months.rounded())) мес"
        }

        let years = days / 365.25
        return years < 10
            ? String(format: "%.1f г", years)
            : "\(Int(years.rounded())) г"
    }
}
