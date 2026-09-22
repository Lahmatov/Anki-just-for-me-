import Foundation

/// Коробки Лейтнера — самый прозрачный из алгоритмов.
///
/// Никакой модели памяти: пять коробок с фиксированными интервалами. Ошибся —
/// вернулся в первую, ответил — поднялся на одну. Полезен, когда хочется
/// понимать расписание целиком, не заглядывая в формулы.
public struct LeitnerScheduler: Scheduler {
    public let id: SchedulerID = .leitner

    public var boxIntervalDays: [Double]

    public init(boxIntervalDays: [Double] = [1, 3, 7, 14, 30]) {
        self.boxIntervalDays = boxIntervalDays.isEmpty ? [1, 3, 7, 14, 30] : boxIntervalDays
    }

    public var boxCount: Int { boxIntervalDays.count }

    public func review(_ state: ReviewState, grade: Grade, now: Date) -> ReviewState {
        var card = state
        let currentBox = card.box ?? 0
        let lastBox = boxCount - 1

        let nextBox: Int
        switch grade {
        case .again:
            nextBox = 0
            if card.state == .review { card.lapses += 1 }
        case .hard:
            nextBox = currentBox
        case .good:
            nextBox = min(currentBox + 1, lastBox)
        case .easy:
            nextBox = min(currentBox + 2, lastBox)
        }

        card.box = nextBox
        card.state = .review
        card.step = nil

        let intervalDays = boxIntervalDays[nextBox]
        card.due = now.addingTimeInterval(intervalDays * 86_400)
        card.lastReview = now
        card.intervalDays = intervalDays
        card.reps += 1
        return card
    }
}
