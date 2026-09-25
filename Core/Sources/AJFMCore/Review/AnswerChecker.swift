import Foundation

/// Насколько введённый ответ совпал с ожидаемым.
public struct AnswerCheck: Equatable, Sendable {
    public enum Verdict: String, Sendable {
        /// Полное совпадение или принятый синоним.
        case correct
        /// Опечатка в один символ — засчитываем, но показываем правильное написание.
        case typo
        case wrong
    }

    public var verdict: Verdict
    /// Вариант ответа, с которым совпало, — его и показываем как эталон.
    public var matched: String?
    /// Пояснение для экрана: чем именно ответ отличался.
    public var hint: String?

    public init(verdict: Verdict, matched: String? = nil, hint: String? = nil) {
        self.verdict = verdict
        self.matched = matched
        self.hint = hint
    }

    public var isAccepted: Bool { verdict != .wrong }
}

/// Сравнение введённого ответа с ожидаемым.
///
/// Задача — не придираться к мелочам, из-за которых человек начинает злиться и
/// бросать («The leverage» против «leverage»), но и не прощать реальных ошибок.
/// Поэтому регистр, лишние пробелы, финальная точка и артикли игнорируются всегда,
/// а опечатка в один символ засчитывается отдельным вердиктом — кроме карточек
/// на правописание, где как раз важна точность.
public enum AnswerChecker {

    public static func check(
        input: String,
        expected: String,
        synonyms: [String] = [],
        strict: Bool = false
    ) -> AnswerCheck {
        let typed = normalize(input)
        guard !typed.isEmpty else {
            return AnswerCheck(verdict: .wrong, matched: nil, hint: tr("Пустой ответ", "Resposta vazia", "Empty answer"))
        }

        let candidates = ([expected] + synonyms)
            .map { (original: $0, normalized: normalize($0)) }
            .filter { !$0.normalized.isEmpty }

        // Полное совпадение после нормализации.
        for candidate in candidates where candidate.normalized == typed {
            return AnswerCheck(verdict: .correct, matched: candidate.original, hint: nil)
        }

        // Совпадение с точностью до артикля или частицы «to».
        let typedCore = TermNormalizer.normalize(typed)
        for candidate in candidates where TermNormalizer.normalize(candidate.normalized) == typedCore {
            return AnswerCheck(
                verdict: .correct, matched: candidate.original,
                hint: tr("Засчитано: артикли и «to» не считаются ошибкой",
                         "Aceite: artigos e «to» não contam como erro",
                         "Accepted: articles and “to” don't count as mistakes"))
        }

        if !strict {
            for candidate in candidates {
                // На коротких словах опечатка в один символ — это уже другое слово
                // (cat/cut, bad/bed), поэтому поблажка только от четырёх букв.
                guard candidate.normalized.count >= 4 else { continue }
                if editDistance(typed, candidate.normalized, limit: 1) <= 1 {
                    return AnswerCheck(
                        verdict: .typo, matched: candidate.original,
                        hint: tr("Опечатка: правильно «\(candidate.original)»",
                                 "Gralha: o correto é «\(candidate.original)»",
                                 "Typo: it's “\(candidate.original)”"))
                }
            }
        }

        return AnswerCheck(
            verdict: .wrong, matched: candidates.first?.original,
            hint: candidates.first.map {
                tr("Правильно: «\($0.original)»",
                   "Correto: «\($0.original)»",
                   "Correct: “\($0.original)”")
            })
    }

    /// Приводит ответ к виду, в котором его можно сравнивать: регистр, пробелы,
    /// финальная пунктуация и типографские апострофы.
    static func normalize(_ text: String) -> String {
        var result = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        result = result
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        result = result.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        while let last = result.last, last.isPunctuation, last != "'" {
            result.removeLast()
        }
        return result
    }

    /// Расстояние Левенштейна с ранним выходом: считать точное значение незачем,
    /// нас интересует только «отличается не больше чем на limit».
    static func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            var rowBest = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost)
                rowBest = min(rowBest, current[j])
            }
            if rowBest > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
