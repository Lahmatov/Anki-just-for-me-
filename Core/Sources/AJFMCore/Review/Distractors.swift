import Foundation

/// Неправильные варианты для карточки «Выбери перевод».
///
/// Раньше они брались из переводов всех слов подряд. Если в базе смешались
/// наборы с русскими переводами и с английскими толкованиями, на одной
/// карточке оказывались «раскрыть прикрытие» и три фразы по-английски — и
/// ответ угадывался по языку, а не по смыслу. Теперь варианты — на том же
/// языке, что и правильный, и примерно той же длины.
public enum Distractors {

    /// Грубое определение языка — только чтобы не смешивать варианты.
    public enum Script: Equatable, Sendable {
        case cyrillic
        case english
        /// Латиница не по-английски: португальский и прочее.
        case otherLatin
        case unknown
    }

    public static func script(of text: String) -> Script {
        var cyrillic = 0
        var latin = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x0400...0x04FF: cyrillic += 1
            case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F: latin += 1
            default: break
            }
        }
        if cyrillic == 0 && latin == 0 { return .unknown }
        if cyrillic >= latin { return .cyrillic }
        return looksPortugueseOrOther(text) ? .otherLatin : .english
    }

    /// Португальский отличают диакритика и служебные слова; всё остальное
    /// на латинице считаем английским — толкования в наборах английские.
    private static func looksPortugueseOrOther(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.rangeOfCharacter(from: CharacterSet(charactersIn: "ãõçáàâéêíóôú")) != nil {
            return true
        }
        let words = Set(lowered.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let portuguese: Set<String> = ["de", "que", "um", "uma", "para", "com", "não", "do", "da",
                                       "dos", "das", "em", "no", "na", "se", "por", "ou", "o", "os", "as"]
        let english: Set<String> = ["the", "to", "of", "and", "a", "an", "is", "that", "in", "or",
                                    "by", "with", "for", "someone", "something", "it", "be"]
        return words.intersection(portuguese).count > words.intersection(english).count
    }

    /// До `count` неправильных вариантов: сначала того же языка и похожей
    /// длины. Чужого языка не берём вовсе — лучше три варианта вместо
    /// четырёх, чем подсказка «правильный — единственный по-русски».
    public static func pick<G: RandomNumberGenerator>(
        correct: String, pool: [String], count: Int = 3, using generator: inout G
    ) -> [String] {
        let target = script(of: correct)
        let normalizedCorrect = normalize(correct)
        var seen: Set<String> = [normalizedCorrect]
        let candidates = pool.filter { candidate in
            let key = normalize(candidate)
            guard !key.isEmpty, seen.insert(key).inserted else { return false }
            return target == .unknown || script(of: candidate) == target
        }
        // Похожая длина — чтобы правильный не выделялся тем, что он
        // единственный короткий среди длинных толкований.
        let length = Double(correct.count)
        let close = candidates.filter { candidate in
            let ratio = Double(candidate.count) / max(length, 1)
            return ratio >= 0.4 && ratio <= 2.5
        }
        var chosen = Array(close.shuffled(using: &generator).prefix(count))
        if chosen.count < count {
            let rest = candidates.filter { !chosen.contains($0) }.shuffled(using: &generator)
            chosen += rest.prefix(count - chosen.count)
        }
        return chosen
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
