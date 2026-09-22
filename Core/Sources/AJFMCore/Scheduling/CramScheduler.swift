import Foundation

/// Зубрёжка в духе режима Learn у Quizlet.
///
/// Не интервальный алгоритм вовсе: карточка крутится внутри сессии, пока не
/// ответишь верно нужное число раз подряд, и только потом уходит на день.
/// Для срочной лексики к поездке — когда интервальное повторение просто
/// не успеет сработать.
public struct CramScheduler: Scheduler {
    public let id: SchedulerID = .cram

    /// Сколько верных ответов подряд считается «на сегодня хватит».
    public var requiredStreak: Int
    /// Через сколько карточка вернётся внутри сессии после ошибки.
    public var retryInterval: TimeInterval
    public var hardInterval: TimeInterval
    public var goodInterval: TimeInterval
    /// Отсрочка после закрытия цели.
    public var settledIntervalDays: Double

    public init(
        requiredStreak: Int = 2,
        retryInterval: TimeInterval = 60,
        hardInterval: TimeInterval = 180,
        goodInterval: TimeInterval = 600,
        settledIntervalDays: Double = 1
    ) {
        self.requiredStreak = max(1, requiredStreak)
        self.retryInterval = retryInterval
        self.hardInterval = hardInterval
        self.goodInterval = goodInterval
        self.settledIntervalDays = settledIntervalDays
    }

    public func review(_ state: ReviewState, grade: Grade, now: Date) -> ReviewState {
        var card = state
        let currentStreak = card.streak ?? 0

        let nextStreak: Int
        var interval: TimeInterval
        switch grade {
        case .again:
            nextStreak = 0
            interval = retryInterval
            if card.state == .review { card.lapses += 1 }
        case .hard:
            // Ответил, но с трудом — серия не растёт, вернёмся скоро.
            nextStreak = currentStreak
            interval = hardInterval
        case .good:
            nextStreak = currentStreak + 1
            interval = goodInterval
        case .easy:
            nextStreak = currentStreak + 2
            interval = goodInterval
        }

        card.streak = nextStreak

        if nextStreak >= requiredStreak {
            card.state = .review
            card.step = nil
            card.intervalDays = settledIntervalDays
            interval = settledIntervalDays * 86_400
        } else {
            card.state = .learning
            card.step = nextStreak
            card.intervalDays = interval / 86_400
        }

        card.due = now.addingTimeInterval(interval)
        card.lastReview = now
        card.reps += 1
        return card
    }
}
