import Foundation

/// Когда праздновать.
///
/// Праздник, который случается на каждом экране, перестаёт быть праздником
/// уже на третий день. Поэтому правила строгие: цель дня — один раз в день
/// и только в момент, когда её перешли; серия — только на круглых отметках;
/// сессия — только когда в ней было что отвечать и ответы хорошие.
public enum Celebration {

    public enum Level: Equatable, Sendable {
        case none
        /// Хорошая сессия: лось радуется, без конфетти.
        case good
        /// Отличная сессия, цель дня, отметка серии: конфетти.
        case big
    }

    /// Отметки серии, которые стоит отпраздновать.
    public static let streakMilestones = [3, 7, 14, 30, 50, 100, 150, 200, 365, 500, 1000]

    /// Конфетти за цель дня — если её перешли только что и сегодня ещё не праздновали.
    /// `day` — ключ дня («2026-09-30»), с учётом часа, когда день кончается.
    public static func goalReached(progressBefore: Double, progressAfter: Double,
                                   celebratedDay: String?, day: String) -> Bool {
        progressBefore < 1 && progressAfter >= 1 && celebratedDay != day
    }

    /// Отметка серии, которую только что достигли, или nil.
    public static func streakMilestone(previous: Int, current: Int) -> Int? {
        guard current > previous else { return nil }
        return streakMilestones.last { $0 > previous && $0 <= current }
    }

    /// Итог сессии. Конфетти — только за отличную сессию хотя бы из пяти
    /// ответов: две карточки без ошибок — не повод, это был заход на минуту.
    public static func session(answered: Int, accuracy: Double) -> Level {
        guard answered > 0, accuracy.isFinite else { return .none }
        if answered >= 5, accuracy >= 0.95 { return .big }
        return accuracy >= 0.7 ? .good : .none
    }
}
