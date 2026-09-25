import Foundation

/// Уровень владения языком по общеевропейской шкале.
public enum CEFRLevel: String, CaseIterable, Codable, Comparable, Sendable {
    case a1 = "A1", a2 = "A2", b1 = "B1", b2 = "B2", c1 = "C1", c2 = "C2"

    public static func < (lhs: CEFRLevel, rhs: CEFRLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        CEFRLevel.allCases.firstIndex(of: self) ?? 0
    }

    /// Следующая ступень: новые слова полезнее всего чуть выше своего уровня.
    public var next: CEFRLevel {
        let all = CEFRLevel.allCases
        return all[min(rank + 1, all.count - 1)]
    }
}
