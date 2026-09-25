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
    /// - Parameter desiredRetention: доля карточек, которую хочется помнить
    ///   на момент повторения. Учитывается только FSRS — остальные алгоритмы
    ///   не умеют подстраивать интервалы под целевое удержание.
    public static func make(
        _ id: SchedulerID, desiredRetention: Double = 0.9
    ) -> any Scheduler {
        switch id {
        case .fsrs6: return FSRS6Scheduler(desiredRetention: desiredRetention)
        case .sm2: return SM2Scheduler()
        case .leitner: return LeitnerScheduler()
        case .cram: return CramScheduler()
        }
    }
}

/// Человекочитаемая длительность: «10 мин», «3 дня», «2.5 мес».
public enum IntervalFormatter {
    public static func short(_ interval: TimeInterval) -> String {
        // Сокращения, а не склонения: на кнопке оценки место есть
        // для «3 дн», но не для «3 дня».
        let minute = tr("мин", "min", "min")
        let hour = tr("ч", "h", "h")
        let day = tr("дн", "d", "d")
        let month = tr("мес", "mês", "mo")
        let year = tr("г", "a", "y")

        let minutes = interval / 60
        if minutes < 1 { return "<1 \(minute)" }
        if minutes < 60 { return "\(Int(minutes.rounded())) \(minute)" }

        let hours = minutes / 60
        if hours < 24 { return "\(Int(hours.rounded())) \(hour)" }

        let days = hours / 24
        if days < 30 { return "\(Int(days.rounded())) \(day)" }

        let months = days / 30.44
        if months < 12 {
            return months < 10
                ? String(format: "%.1f ", months) + month
                : "\(Int(months.rounded())) \(month)"
        }

        let years = days / 365.25
        return years < 10
            ? String(format: "%.1f ", years) + year
            : "\(Int(years.rounded())) \(year)"
    }
}
