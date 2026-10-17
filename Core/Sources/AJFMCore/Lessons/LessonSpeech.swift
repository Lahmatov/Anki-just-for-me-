import Foundation

/// «Расскажи об уроке»: какие слова урока прозвучали в рассказе.
///
/// Мерка мягкая и честно приблизительная: слово засчитывается и в другой
/// форме («comi» за «comer»), потому что смысл упражнения — заговорить
/// словами урока, а не сдать грамматику. Неправильные формы глаголов
/// узнаются через спряжение: «tenho» по одному началу слова за «ter» не узнать.
public enum LessonSpeech {

    public struct Result: Equatable, Sendable {
        public var used: [String]
        public var unused: [String]

        public init(used: [String], unused: [String]) {
            self.used = used
            self.unused = unused
        }

        public var coverage: Double {
            let total = used.count + unused.count
            return total == 0 ? 0 : Double(used.count) / Double(total)
        }
    }

    public static func check(transcript: String, terms: [String], language: StudyLanguage) -> Result {
        let spoken = Set(words(transcript))
        var used: [String] = []
        var unused: [String] = []
        var seen = Set<String>()
        for term in terms {
            let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seen.insert(fold(clean)).inserted else { continue }
            let keys = keyWords(clean, language: language)
            guard !keys.isEmpty else { continue }
            let forms = verbForms(clean, language: language)
            let heard = keys.enumerated().allSatisfy { index, key in
                spoken.contains { said in
                    matches(said, key) || (index == 0 && forms.contains(said))
                }
            }
            if heard { used.append(clean) } else { unused.append(clean) }
        }
        return Result(used: used, unused: unused)
    }

    /// Артикли и служебные частицы не считаются: «o comboio» прозвучал,
    /// если прозвучал «comboio».
    static let skipped: [StudyLanguage: Set<String>] = [
        .english: ["the", "a", "an", "to", "be", "sb", "sth", "someone", "something"],
        .portuguese: ["o", "a", "os", "as", "um", "uma", "de", "do", "da", "se", "alguém", "algo"],
        .italian: ["il", "lo", "la", "i", "gli", "le", "un", "uno", "una", "di", "si", "qualcuno",
                   "qualcosa"],
    ]

    static func keyWords(_ term: String, language: StudyLanguage) -> [String] {
        var list = words(term).map { word -> String in
            // levantar-se → levantar, alzarsi — как есть: «mi alzo» узнаётся по началу.
            word.hasSuffix("-se") ? String(word.dropLast(3)) : word
        }
        list.removeAll { skipped[language]?.contains($0) == true }
        return list
    }

    /// Совпадение с точностью до окончания: общее начало — всё слово без
    /// последних трёх букв, но не короче трёх; длина отличается не больше чем на три.
    static func matches(_ said: String, _ key: String) -> Bool {
        if said == key { return true }
        let stemLength = max(3, key.count - 3)
        guard key.count >= 3, said.count >= stemLength,
              abs(said.count - key.count) <= 3 else { return false }
        return said.hasPrefix(String(key.prefix(stemLength)))
    }

    static func verbForms(_ term: String, language: StudyLanguage) -> Set<String> {
        var forms = Set<String>()
        for tense in Tense.allCases {
            guard let conjugation = Conjugator.conjugate(term, language: language, tense: tense) else { continue }
            for form in conjugation.forms {
                // Берём сам глагол: в итальянском прошедшем — причастие, а не «ho».
                let parts = form.form.split(separator: " ").map { fold(String($0)) }
                if let verb = parts.first(where: { !["ho", "hai", "ha", "abbiamo", "avete", "hanno",
                                                    "sono", "sei", "è", "e", "siamo", "siete",
                                                    "mi", "ti", "si", "ci", "vi"].contains($0) }) {
                    forms.insert(verb.components(separatedBy: "-").first ?? verb)
                }
            }
        }
        return forms
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "'-")).inverted)
            .map { fold($0.trimmingCharacters(in: CharacterSet(charactersIn: "'-"))) }
            .filter { !$0.isEmpty }
    }

    static func fold(_ word: String) -> String {
        word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
