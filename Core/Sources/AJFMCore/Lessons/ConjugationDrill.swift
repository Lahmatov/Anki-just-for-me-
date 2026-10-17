import Foundation

/// Задание тренажёра спряжения: «comer — nós, presente» → «comemos».
public struct ConjugationTask: Equatable, Sendable, Identifiable {
    public var id: Int
    public var verb: String
    public var tense: Tense
    public var person: String
    public var answer: String
    /// Вся таблица — показать после ответа.
    public var table: Conjugation

    public init(id: Int, verb: String, tense: Tense, person: String, answer: String, table: Conjugation) {
        self.id = id
        self.verb = verb
        self.tense = tense
        self.person = person
        self.answer = answer
        self.table = table
    }
}

public enum ConjugationDrill {
    public static let defaultCount = 12
    /// Лиц на глагол и время: всю таблицу подряд скучно, одно лицо — мало.
    static let personsPerTable = 2

    /// Глаголы урока: помечены глаголом или фразовым глаголом и спрягаются.
    public static func verbs(notes: [NoteData], language: StudyLanguage) -> [String] {
        var seen = Set<String>()
        return notes.compactMap { note in
            guard note.partOfSpeech == .verb || note.partOfSpeech == .phrasalVerb else { return nil }
            let term = note.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Conjugator.canConjugate(term, language: language),
                  seen.insert(term.lowercased()).inserted else { return nil }
            return term
        }
    }

    public static func make<G: RandomNumberGenerator>(
        verbs: [String], language: StudyLanguage, count: Int = defaultCount, using generator: inout G
    ) -> [ConjugationTask] {
        var tasks: [ConjugationTask] = []
        for verb in verbs.shuffled(using: &generator) {
            for tense in Tense.allCases {
                guard let table = Conjugator.conjugate(verb, language: language, tense: tense) else { continue }
                for form in table.forms.shuffled(using: &generator).prefix(personsPerTable) {
                    tasks.append(ConjugationTask(id: tasks.count, verb: table.verb, tense: tense,
                                                 person: form.person, answer: form.form, table: table))
                }
            }
        }
        return Array(tasks.shuffled(using: &generator).prefix(max(count, 0)))
            .enumerated().map { index, task in
                var task = task
                task.id = index
                return task
            }
    }
}
