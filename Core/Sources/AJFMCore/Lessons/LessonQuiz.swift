import Foundation

/// Вопрос мини-теста по уроку: выбрать один из вариантов.
public struct QuizQuestion: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        /// Слово → выбрать перевод.
        case meaning
        /// Перевод → выбрать слово.
        case word
        /// Фраза с пропуском → выбрать слово для пропуска.
        case gap
    }

    public var id: Int
    public var kind: Kind
    public var prompt: String
    public var choices: [String]
    public var answer: String

    public init(id: Int, kind: Kind, prompt: String, choices: [String], answer: String) {
        self.id = id
        self.kind = kind
        self.prompt = prompt
        self.choices = choices
        self.answer = answer
    }
}

/// Мини-тест по уроку: десяток вопросов на выбор из слов этого урока.
///
/// Неправильные варианты берутся из того же урока — так тест проверяет,
/// различаешь ли ты слова урока между собой, а не угадываешь «единственное
/// знакомое». Тест не трогает расписание повторений: это проверка, а не
/// занятие, и его результат идёт только в карту уроков.
public enum LessonQuiz {
    /// Урок на карте пройден, когда слова начаты и тест сдан на 80%.
    public static let passScore = 0.8
    public static let defaultCount = 10

    public static func make<G: RandomNumberGenerator>(
        notes: [NoteData], count: Int = defaultCount, using generator: inout G
    ) -> [QuizQuestion] {
        let usable = unique(notes.filter {
            !clean($0.term).isEmpty && !clean($0.translation).isEmpty
        })
        guard usable.count >= 2, count > 0 else { return [] }
        let terms = usable.map { clean($0.term) }
        let translations = usable.map { clean($0.translation) }

        var questions: [QuizQuestion] = []
        for (index, note) in usable.shuffled(using: &generator).enumerated() {
            guard questions.count < count else { break }
            let term = clean(note.term)
            let translation = clean(note.translation)
            let kind: QuizQuestion.Kind
            if index % 3 == 2, let gap = gapSentence(note) {
                kind = .gap
                let wrong = Distractors.pick(correct: term, pool: terms, using: &generator)
                guard !wrong.isEmpty else { continue }
                questions.append(QuizQuestion(
                    id: questions.count, kind: kind, prompt: gap,
                    choices: ([term] + wrong).shuffled(using: &generator), answer: term))
                continue
            }
            kind = index.isMultiple(of: 2) ? .meaning : .word
            let (prompt, answer, pool) = kind == .meaning
                ? (term, translation, translations)
                : (translation, term, terms)
            let wrong = Distractors.pick(correct: answer, pool: pool, using: &generator)
            guard !wrong.isEmpty else { continue }
            questions.append(QuizQuestion(
                id: questions.count, kind: kind, prompt: prompt,
                choices: ([answer] + wrong).shuffled(using: &generator), answer: answer))
        }
        return questions
    }

    /// Доля верных ответов; ответа нет — вопрос не засчитан.
    public static func score(_ questions: [QuizQuestion], answers: [Int: String]) -> Double {
        guard !questions.isEmpty else { return 0 }
        let right = questions.filter { answers[$0.id] == $0.answer }.count
        return Double(right) / Double(questions.count)
    }

    public static func passed(_ score: Double) -> Bool { score >= passScore - 0.0001 }

    /// Пропуск — только если в примере действительно есть «___».
    static func gapSentence(_ note: NoteData) -> String? {
        guard let cloze = note.cloze.map(clean), cloze.contains("___") else { return nil }
        return cloze
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Одно слово дважды (урок вставили два раза) — один вопрос.
    private static func unique(_ notes: [NoteData]) -> [NoteData] {
        var seen = Set<String>()
        return notes.filter { seen.insert(TermNormalizer.normalize($0.term)).inserted }
    }
}
