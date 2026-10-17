import Foundation

/// Тренажёры урока (P-69): одно умение за раз на словах одного урока.
///
/// В отличие от повторений, тренажёр не двигает расписание: его можно
/// гонять сколько угодно перед занятием, не ломая интервалы. Расписание —
/// за обычными карточками урока.
public enum DrillMode: String, CaseIterable, Sendable, Identifiable {
    /// Перевод → напиши слово или фразу.
    case translation
    /// Пример с пропуском → впиши слово.
    case cloze
    /// Послушай фразу → запиши её.
    case dictation
    /// Скажи вслух.
    case pronunciation

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .translation: return tr("Перевод фраз", "Tradução", "Translation")
        case .cloze: return tr("Пропуски", "Lacunas", "Gaps")
        case .dictation: return tr("Диктант", "Ditado", "Dictation")
        case .pronunciation: return tr("Произношение", "Pronúncia", "Pronunciation")
        }
    }
}

/// Одно задание тренажёра.
public struct DrillItem: Equatable, Sendable, Identifiable {
    public var id: Int
    /// Что показать: перевод, фраза с пропуском или ничего (диктант — на слух).
    public var prompt: String
    /// Подсказка под заданием: перевод фразы.
    public var hint: String?
    /// Что озвучить; для диктанта и произношения — сама фраза.
    public var spoken: String?
    public var answer: String
    public var synonyms: [String]

    public init(id: Int, prompt: String, hint: String? = nil, spoken: String? = nil,
                answer: String, synonyms: [String] = []) {
        self.id = id
        self.prompt = prompt
        self.hint = hint
        self.spoken = spoken
        self.answer = answer
        self.synonyms = synonyms
    }
}

public enum LessonDrill {
    /// Пример длиннее — уже не диктант, а изложение.
    public static let dictationLimit = 160

    public static func items(notes: [NoteData], mode: DrillMode) -> [DrillItem] {
        var seen = Set<String>()
        let usable = notes.filter {
            !trim($0.term).isEmpty && seen.insert(TermNormalizer.normalize($0.term)).inserted
        }
        var items: [DrillItem] = []
        for note in usable {
            let term = trim(note.term)
            let translation = trim(note.translation)
            let id = items.count
            switch mode {
            case .translation:
                guard !translation.isEmpty else { continue }
                items.append(DrillItem(id: id, prompt: translation, answer: term,
                                       synonyms: note.synonyms ?? []))
            case .cloze:
                guard let cloze = note.cloze.map(trim), cloze.contains("___") else { continue }
                items.append(DrillItem(id: id, prompt: cloze, hint: translation.isEmpty ? nil : translation,
                                       answer: term, synonyms: note.synonyms ?? []))
            case .dictation:
                // Фраза из примера — ради неё диктант и нужен; нет примера — само слово.
                let example = trim(note.example ?? "")
                let useExample = !example.isEmpty && example.count <= dictationLimit
                let text = useExample ? example : term
                let hint = useExample ? trim(note.exampleTranslation ?? "") : translation
                items.append(DrillItem(id: id, prompt: "", hint: hint.isEmpty ? nil : hint,
                                       spoken: text, answer: text))
            case .pronunciation:
                items.append(DrillItem(id: id, prompt: term, hint: translation.isEmpty ? nil : translation,
                                       spoken: term, answer: term))
            }
        }
        return items
    }

    /// Какие тренажёры есть у урока: пропуски — только если есть примеры с пропуском.
    public static func availableModes(notes: [NoteData]) -> [DrillMode] {
        DrillMode.allCases.filter { !items(notes: notes, mode: $0).isEmpty }
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
