import Foundation

/// Предложение из субтитров, подобранное для карточки.
public struct MinedSentence: Equatable, Sendable {
    public var term: String
    public var sentence: String
    /// То же предложение с пропуском на месте слова.
    public var cloze: String
    public var timecode: TimeInterval
}

/// Подбор живых примеров из субтитров уже просмотренной серии.
///
/// Это и есть sentence mining из методик Refold и Migaku: пример из сцены,
/// которую ты видел и понял, работает заметно лучше словарной фразы —
/// у него уже есть контекст и эмоция, за которые цепляется память.
public enum SentenceMiner {

    /// Насколько длинной может быть фраза, чтобы остаться полезной карточкой.
    public static let maxWords = 18
    public static let minWords = 3

    /// Ищет лучший пример для слова.
    public static func bestSentence(
        for term: String, in track: SubtitleTrack
    ) -> MinedSentence? {
        let candidates = track.cues
            .filter { matches(cue: $0.text, term: term) && isUsable($0.text) }
            // Короткие фразы запоминаются лучше, но совсем обрывки бесполезны.
            .sorted { wordCount($0.text) < wordCount($1.text) }

        guard let cue = candidates.first else { return nil }
        return MinedSentence(
            term: term,
            sentence: cue.text,
            cloze: makeCloze(sentence: cue.text, term: term),
            timecode: cue.start)
    }

    /// Подбирает примеры сразу для списка слов.
    public static func mine(
        terms: [String], in track: SubtitleTrack
    ) -> [String: MinedSentence] {
        var result: [String: MinedSentence] = [:]
        for term in terms {
            if let sentence = bestSentence(for: term, in: track) {
                result[term] = sentence
            }
        }
        return result
    }

    /// Ищет слово в реплике с учётом словоформ: в субтитрах «pull off»
    /// почти всегда выглядит как «pulled that off».
    static func matches(cue: String, term: String) -> Bool {
        let normalizedTerm = TermNormalizer.normalize(term)
        guard !normalizedTerm.isEmpty else { return false }

        let normalizedCue = TermNormalizer.normalize(cue)
        // Подстрокой ищем только фразу целиком: для одного слова это нашло бы
        // «go» внутри «good».
        if normalizedTerm.contains(" "), normalizedCue.contains(normalizedTerm) {
            return true
        }

        let parts = normalizedTerm.split(separator: " ").map(String.init)
        let cueWords = normalizedCue
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }

        return parts.allSatisfy { part in
            cueWords.contains { word in
                word == part || (part.count >= 4 && word.hasPrefix(part))
            }
        }
    }

    static func isUsable(_ text: String) -> Bool {
        let words = wordCount(text)
        return words >= minWords && words <= maxWords
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Заменяет слово на пропуск, сохраняя форму предложения.
    ///
    /// Заменяется слово целиком: наивный поиск подстроки вырезал бы «go»
    /// из середины «good». Форма слова в субтитрах обычно отличается от
    /// словарной, поэтому для достаточно длинного слова допускается
    /// совпадение по началу — «pull» находит «pulled».
    public static func makeCloze(sentence: String, term: String) -> String {
        let cleanTerm = TermNormalizer.normalize(term)
        guard !cleanTerm.isEmpty else { return sentence }

        if cleanTerm.contains(" "),
           let range = sentence.range(of: cleanTerm, options: .caseInsensitive) {
            return sentence.replacingCharacters(in: range, with: "___")
        }

        let stem = String(cleanTerm.split(separator: " ").first ?? "")
        guard !stem.isEmpty else { return sentence }

        var replaced = false
        let rebuilt = sentence
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                guard !replaced else { return String(word) }
                let bare = word
                    .trimmingCharacters(in: .punctuationCharacters)
                    .lowercased()
                if bare == stem || (stem.count >= 4 && bare.hasPrefix(stem)) {
                    replaced = true
                    // Пунктуацию вокруг слова сохраняем: «leverage.» → «___.»
                    let raw = String(word)
                    let leading = String(raw.prefix { $0.isPunctuation })
                    let trailing = String(
                        raw.reversed().prefix { $0.isPunctuation }.reversed())
                    return leading + "___" + trailing
                }
                return String(word)
            }
        return replaced ? rebuilt.joined(separator: " ") : sentence
    }
}
