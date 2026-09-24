import Foundation

public enum LaunchAnimationStyle: String, Equatable, Sendable {
    /// Полная заставка: колода раскладывается и уходит.
    case full
    /// Короткий уход знака — для повторных запусков за день.
    case brief
    /// Без анимации вовсе.
    case none

    public var duration: TimeInterval {
        switch self {
        case .full: return LaunchAnimationPolicy.fullDuration
        case .brief: return LaunchAnimationPolicy.briefDuration
        case .none: return 0
        }
    }
}

/// Когда и какую анимацию показывать при запуске.
///
/// Apple прямо не рекомендует заставки: запуск должен ощущаться мгновенным,
/// искусственные задержки недопустимы. Поэтому анимация здесь устроена так,
/// чтобы ничего не задерживать: системный экран запуска статичен и совпадает
/// по цвету с первым кадром заставки, данные грузятся под ней, а нажатие
/// её пропускает.
///
/// И она не должна надоедать. Полная — один раз за учебный день, остальные
/// запуски получают короткий уход знака. Приложение открывают по нескольку
/// раз в день, и секунда анимации на каждый раз превращается в трение.
public enum LaunchAnimationPolicy {
    /// Заметно короче трёх секунд, которые считаются пределом для таких экранов.
    public static let fullDuration: TimeInterval = 1.2
    public static let briefDuration: TimeInterval = 0.35

    public static func style(
        reduceMotion: Bool,
        lastFullShown: Date?,
        now: Date = Date(),
        cutoffHour: Int,
        calendar: Calendar = .current
    ) -> LaunchAnimationStyle {
        // Кто выключил движение в системе, тот выключил и заставку.
        guard !reduceMotion else { return .none }
        guard let lastFullShown else { return .full }

        let today = ReviewQueueBuilder.studyDayStart(
            for: now, cutoffHour: cutoffHour, calendar: calendar)
        let shownDay = ReviewQueueBuilder.studyDayStart(
            for: lastFullShown, cutoffHour: cutoffHour, calendar: calendar)
        return shownDay < today ? .full : .brief
    }
}
