import Foundation

/// Русские окончания при числах: 1 день, 2 дня, 5 дней, 11 дней, 21 день.
///
/// Мелочь, но «2 дней» или «5 раза» режет глаз каждый раз, когда попадается,
/// а попадается постоянно — в счётчиках, сериях и подсказках.
public enum RussianPlural {

    public static func form(_ count: Int, one: String, few: String, many: String) -> String {
        // magnitude, а не abs: abs(Int.min) не помещается в Int и роняет процесс.
        let value = count.magnitude
        let lastTwo = value % 100
        if (11...14).contains(lastTwo) { return many }
        switch value % 10 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }

    /// Число вместе со словом: «3 дня».
    public static func phrase(_ count: Int, one: String, few: String, many: String) -> String {
        "\(count) \(form(count, one: one, few: few, many: many))"
    }

    public static func days(_ count: Int) -> String {
        phrase(count, one: "день", few: "дня", many: "дней")
    }

    public static func words(_ count: Int) -> String {
        phrase(count, one: "слово", few: "слова", many: "слов")
    }

    public static func cards(_ count: Int) -> String {
        phrase(count, one: "карточка", few: "карточки", many: "карточек")
    }

    /// Винительный падеж — для глаголов: «учить 1 карточку», а не «1 карточка».
    /// Во множественном числе он совпадает с родительным, так что меняется
    /// только форма на единицу.
    public static func cardsAccusative(_ count: Int) -> String {
        phrase(count, one: "карточку", few: "карточки", many: "карточек")
    }
}
