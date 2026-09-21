import Foundation

/// Приведение английского слова или фразы к канонической форме для сравнения.
///
/// Нужно, чтобы «To Pull Off», «pull off» и «  pull  off.  » считались одним и тем же
/// словом при дедупликации импорта.
public enum TermNormalizer {
    private static let leadingArticles = ["the ", "a ", "an "]
    private static let leadingInfinitive = "to "

    public static func normalize(_ term: String) -> String {
        var s = term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Схлопываем любые пробельные последовательности в один пробел.
        s = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")

        s = stripPrefix(leadingInfinitive, from: s)
        for article in leadingArticles {
            s = stripPrefix(article, from: s)
        }

        // Финальная пунктуация: «pull off.» и «pull off» — одно и то же.
        while let last = s.last, last.isPunctuation {
            s.removeLast()
        }

        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Убираем префикс, только если после него остаётся осмысленный остаток —
    /// иначе слово «to» или «a» нормализовалось бы в пустую строку.
    private static func stripPrefix(_ prefix: String, from s: String) -> String {
        guard s.hasPrefix(prefix) else { return s }
        let rest = String(s.dropFirst(prefix.count))
        return rest.count >= 2 ? rest : s
    }
}
