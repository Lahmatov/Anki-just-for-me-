import Foundation

/// Насколько разгорелся огонёк серии: чем дольше серия, тем он больше и ярче.
///
/// Рост логарифмический: разница между первым и седьмым днём должна быть
/// видна сразу, а между сотым и сто седьмым — уже нет, иначе к полугоду
/// огонёк не поместился бы в карточку. После 60 дней — предел.
public enum StreakFlame {
    public static let fullAtDays = 60

    /// 0 — серии нет, 1 — предел.
    public static func intensity(days: Int) -> Double {
        guard days > 0 else { return 0 }
        let capped = Double(min(days, fullAtDays))
        return log(1 + capped) / log(1 + Double(fullAtDays))
    }

    /// Размер значка: от базового до почти вдвое больше.
    public static func size(days: Int, base: Double = 30) -> Double {
        base * (1 + 0.8 * intensity(days: days))
    }

    /// Ступень цвета: жёлтый в начале, оранжевый с недели, красный с месяца,
    /// фиолетовый «синий огонь» после двух месяцев.
    public enum Stage: Int, Sendable, CaseIterable {
        case spark, flame, blaze, blue
    }

    public static func stage(days: Int) -> Stage {
        switch days {
        case ..<7: return .spark
        case 7..<30: return .flame
        case 30..<fullAtDays: return .blaze
        default: return .blue
        }
    }
}
