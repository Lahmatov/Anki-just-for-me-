import Foundation
import SwiftData
import AJFMCore

// Модель данных повторяет структуру Anki: одна словарная единица (Note) порождает
// несколько карточек (Card), у каждой свой независимый интервал. Обоснование —
// docs/architecture.md, решение P-2.
//
// Перечисления хранятся строками, а не как Codable-значения: так схема переживает
// добавление нового типа карточки без миграции базы.

@Model
final class Folder {
    var name: String = ""
    var createdAt: Date = Date()

    var parent: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    var children: [Folder] = []

    @Relationship(deleteRule: .cascade, inverse: \Deck.folder)
    var decks: [Deck] = []

    init(name: String, parent: Folder? = nil) {
        self.name = name
        self.parent = parent
        self.createdAt = Date()
    }

    /// Путь от корня, как он записывается в поле `folder` файла набора.
    var path: String {
        var parts: [String] = []
        var current: Folder? = self
        // Защита от цикла: в базе его быть не должно, но обход не должен зависать.
        var guardCounter = 0
        while let folder = current, guardCounter < 64 {
            parts.insert(folder.name, at: 0)
            current = folder.parent
            guardCounter += 1
        }
        return parts.joined(separator: "/")
    }

    var totalNoteCount: Int {
        decks.reduce(0) { $0 + $1.notes.count }
            + children.reduce(0) { $0 + $1.totalNoteCount }
    }
}

@Model
final class Deck {
    var name: String = ""
    var schedulerRaw: String = SchedulerID.fsrs6.rawValue
    var cardTypesRaw: [String] = []
    var source: String?
    var createdAt: Date = Date()

    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Note.deck)
    var notes: [Note] = []

    init(
        name: String,
        scheduler: SchedulerID,
        cardTypes: [CardType],
        source: String? = nil,
        folder: Folder? = nil
    ) {
        self.name = name
        self.schedulerRaw = scheduler.rawValue
        self.cardTypesRaw = cardTypes.map(\.rawValue)
        self.source = source
        self.folder = folder
        self.createdAt = Date()
    }

    var scheduler: SchedulerID {
        get { SchedulerID(rawValue: schedulerRaw) ?? .fsrs6 }
        set { schedulerRaw = newValue.rawValue }
    }

    var cardTypes: [CardType] {
        get { cardTypesRaw.compactMap(CardType.init(rawValue:)) }
        set { cardTypesRaw = newValue.map(\.rawValue) }
    }
}

@Model
final class Note {
    var term: String = ""
    /// Каноническая форма для дедупликации, см. TermNormalizer.
    var normalizedTerm: String = ""
    var translation: String = ""
    var ipa: String?
    var partOfSpeechRaw: String?
    var example: String?
    var exampleTranslation: String?
    var cloze: String?
    var synonyms: [String] = []
    var userNote: String?
    var tags: [String] = []
    var difficultyRaw: String?
    var audio: String?
    var createdAt: Date = Date()

    var deck: Deck?

    @Relationship(deleteRule: .cascade, inverse: \Card.note)
    var cards: [Card] = []

    init(data: NoteData, deck: Deck? = nil) {
        self.term = data.term.trimmingCharacters(in: .whitespacesAndNewlines)
        self.normalizedTerm = TermNormalizer.normalize(data.term)
        self.translation = data.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ipa = data.ipa
        self.partOfSpeechRaw = data.partOfSpeech?.rawValue
        self.example = data.example
        self.exampleTranslation = data.exampleTranslation
        self.cloze = data.cloze
        self.synonyms = data.synonyms ?? []
        self.userNote = data.note
        self.tags = data.tags ?? []
        self.difficultyRaw = data.difficulty?.rawValue
        self.audio = data.audio
        self.deck = deck
        self.createdAt = Date()
    }

    var partOfSpeech: PartOfSpeech? {
        partOfSpeechRaw.flatMap(PartOfSpeech.init(rawValue:))
    }

    var difficulty: Difficulty? {
        difficultyRaw.flatMap(Difficulty.init(rawValue:))
    }

    /// Обратное преобразование в формат файла — для экспорта и бэкапа.
    var asNoteData: NoteData {
        NoteData(
            term: term,
            translation: translation,
            ipa: ipa,
            partOfSpeech: partOfSpeech,
            example: example,
            exampleTranslation: exampleTranslation,
            cloze: cloze,
            synonyms: synonyms.isEmpty ? nil : synonyms,
            note: userNote,
            tags: tags.isEmpty ? nil : tags,
            difficulty: difficulty,
            audio: audio
        )
    }
}

@Model
final class Card {
    var typeRaw: String = CardType.recognition.rawValue
    var stateRaw: String = LearningState.new.rawValue
    var due: Date = Date()
    var lastReview: Date?
    var intervalDays: Double = 0
    var reps: Int = 0
    var lapses: Int = 0

    // Поля состояния алгоритма. Хранятся явными колонками, а не JSON-строкой:
    // так переключение алгоритма на наборе не теряет прогресс, а состояние
    // видно в отладчике и проверяется тестами.
    var step: Int?
    var stability: Double?
    var difficulty: Double?
    var ease: Double?
    var box: Int?
    var streak: Int?

    var createdAt: Date = Date()

    var note: Note?

    @Relationship(deleteRule: .cascade, inverse: \Review.card)
    var reviews: [Review] = []

    init(type: CardType, due: Date = Date()) {
        self.typeRaw = type.rawValue
        self.stateRaw = LearningState.new.rawValue
        self.due = due
        self.createdAt = Date()
    }

    var type: CardType {
        get { CardType(rawValue: typeRaw) ?? .recognition }
        set { typeRaw = newValue.rawValue }
    }

    var state: LearningState {
        get { LearningState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }

    /// Состояние в том виде, в каком его понимают алгоритмы из ядра.
    var reviewState: ReviewState {
        get {
            ReviewState(
                state: state, due: due, lastReview: lastReview, intervalDays: intervalDays,
                reps: reps, lapses: lapses, step: step, stability: stability,
                difficulty: difficulty, ease: ease, box: box, streak: streak)
        }
        set {
            state = newValue.state
            due = newValue.due
            lastReview = newValue.lastReview
            intervalDays = newValue.intervalDays
            reps = newValue.reps
            lapses = newValue.lapses
            step = newValue.step
            stability = newValue.stability
            difficulty = newValue.difficulty
            ease = newValue.ease
            box = newValue.box
            streak = newValue.streak
        }
    }

    /// «Выучено» для наград и статистики — решение P-4 в docs/decisions.md.
    static let matureIntervalDays = ReviewState.matureIntervalDays

    var isMature: Bool { reviewState.isMature }
}

@Model
final class Review {
    var timestamp: Date = Date()
    /// 1 — Again, 2 — Hard, 3 — Good, 4 — Easy.
    var grade: Int = 3
    var timeSpent: Double = 0
    var algorithm: String = ""
    /// Повтор засчитан честно (через сессию), а не проставлен руками.
    /// Награды считаются только по честным — защита от самообмана, задача 5.4.
    var isHonest: Bool = true

    var card: Card?

    init(
        card: Card?, grade: Int, timeSpent: Double, algorithm: String, isHonest: Bool = true
    ) {
        self.card = card
        self.grade = grade
        self.timeSpent = timeSpent
        self.algorithm = algorithm
        self.isHonest = isHonest
        self.timestamp = Date()
    }
}

/// Сохранённый разбор пересказа серии.
@Model
final class RetellSession {
    var createdAt: Date = Date()
    var episodeTitle: String = ""
    var transcript: String = ""
    /// Разбор целиком, сериализованный в JSON.
    var reportJSON: String = ""
    var coverage: Double = 0
    var grammarMistakes: Int = 0
    var cost: Double = 0
    var model: String = ""
    /// Создан ли уже набор карточек по этому разбору.
    var deckCreated: Bool = false

    init(
        episodeTitle: String, transcript: String, report: RetellReport,
        cost: Double, model: String
    ) {
        self.createdAt = Date()
        self.episodeTitle = episodeTitle
        self.transcript = transcript
        self.reportJSON = (try? JSONEncoder().encode(report))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        self.coverage = report.understanding.coverage
        self.grammarMistakes = report.language.grammar.count
        self.cost = cost
        self.model = model
    }

    var report: RetellReport? {
        guard let data = reportJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RetellReport.self, from: data)
    }
}

/// Строка расхода на облачный разбор.
@Model
final class UsageEntry {
    var date: Date = Date()
    var model: String = ""
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cost: Double = 0

    init(record: UsageRecord) {
        self.date = record.date
        self.model = record.model
        self.inputTokens = record.inputTokens
        self.outputTokens = record.outputTokens
        self.cost = record.cost
    }

    var asRecord: UsageRecord {
        UsageRecord(
            date: date, model: model, inputTokens: inputTokens,
            outputTokens: outputTokens, cost: cost)
    }
}
