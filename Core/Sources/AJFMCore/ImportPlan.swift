import Foundation

/// Что именно произойдёт при импорте набора. Строится до записи в базу,
/// чтобы показать пользователю превью и дать отменить.
public struct ImportPlan: Equatable, Sendable {
    public var deckName: String
    /// Путь папки, разобранный по «/». Пустой — набор ляжет в корень.
    public var folderPath: [String]
    public var scheduler: SchedulerID
    public var cardTypes: [CardType]
    public var source: String?

    /// Слова, которых ещё нет.
    public var newNotes: [NoteData]
    /// Слова, которые уже где-то есть.
    public var duplicates: [Duplicate]
    /// Некритичные замечания к файлу.
    public var warnings: [String]

    public var totalCards: Int { newNotes.count * cardTypes.count }

    public struct Duplicate: Equatable, Sendable {
        public var note: NoteData
        /// Название набора, где слово уже лежит, или nil — если дубль внутри самого файла.
        public var existingDeckName: String?

        public var reason: String {
            if let existingDeckName {
                return "уже есть в наборе «\(existingDeckName)»"
            }
            return "повторяется в самом файле"
        }
    }
}

public enum ImportPlanner {
    public static let defaultCardTypes: [CardType] = [.recognition, .recall]
    public static let defaultScheduler: SchedulerID = .fsrs6

    /// - Parameter existingTerms: нормализованный термин → название набора, где он уже лежит.
    public static func plan(
        file: DeckFile,
        existingTerms: [String: String]
    ) -> ImportPlan {
        var warnings: [String] = []

        let cardTypes: [CardType]
        if let declared = file.deck.cardTypes, !declared.isEmpty {
            var seen = Set<CardType>()
            cardTypes = declared.filter { seen.insert($0).inserted }
        } else {
            if file.deck.cardTypes != nil {
                warnings.append("В файле не указано ни одного понятного типа карточек — взяты обычные.")
            }
            cardTypes = defaultCardTypes
        }

        if cardTypes.contains(.cloze) {
            let withoutCloze = file.notes.filter { ($0.cloze ?? "").trimmed.isEmpty }
            if !withoutCloze.isEmpty {
                warnings.append(
                    "Карточка с пропуском не получится у \(withoutCloze.count) слов — нет поля cloze.")
            }
        }

        let scheduler = file.deck.scheduler ?? defaultScheduler
        let folderPath = (file.deck.folder ?? "")
            .split(separator: "/")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }

        var newNotes: [NoteData] = []
        var duplicates: [ImportPlan.Duplicate] = []
        var seenInFile: Set<String> = []

        for note in file.notes {
            let key = TermNormalizer.normalize(note.term)
            if key.isEmpty {
                warnings.append("Слово «\(note.term)» пропущено: после очистки от него ничего не осталось.")
                continue
            }
            if seenInFile.contains(key) {
                duplicates.append(.init(note: note, existingDeckName: nil))
                continue
            }
            seenInFile.insert(key)

            if let deckName = existingTerms[key] {
                duplicates.append(.init(note: note, existingDeckName: deckName))
            } else {
                newNotes.append(note)
            }
        }

        if newNotes.count > 30 {
            warnings.append(
                "\(newNotes.count) новых слов — это много для одной очереди. "
                + "Лимит новых карточек в день всё сгладит, но набор лучше дробить.")
        }

        return ImportPlan(
            deckName: file.deck.name.trimmed,
            folderPath: folderPath,
            scheduler: scheduler,
            cardTypes: cardTypes,
            source: file.deck.source,
            newNotes: newNotes,
            duplicates: duplicates,
            warnings: warnings
        )
    }
}
