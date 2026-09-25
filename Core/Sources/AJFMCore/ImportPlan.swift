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
                return tr("уже есть в наборе «\(existingDeckName)»",
                          "já existe no baralho «\(existingDeckName)»",
                          "already in the deck “\(existingDeckName)”")
            }
            return tr("повторяется в самом файле",
                      "repete-se no próprio ficheiro",
                      "repeated within the file")
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
                warnings.append(tr(
                    "В файле не указано ни одного понятного типа карточек — взяты обычные.",
                    "O ficheiro não indica nenhum tipo de cartão conhecido — usam-se os habituais.",
                    "The file names no known card types — the usual ones are used."))
            }
            cardTypes = defaultCardTypes
        }

        if cardTypes.contains(.cloze) {
            let withoutCloze = file.notes.filter { ($0.cloze ?? "").trimmed.isEmpty }
            if !withoutCloze.isEmpty {
                warnings.append(tr(
                    "Карточка с пропуском не получится у ",
                    "O cartão com lacuna não sai para ",
                    "No fill-in-the-blank card for ")
                    + Counted.words(withoutCloze.count)
                    + tr(" — нет поля cloze.", " — falta o campo cloze.", " — the cloze field is missing."))
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
                warnings.append(tr(
                    "Слово «\(note.term)» пропущено: после очистки от него ничего не осталось.",
                    "A palavra «\(note.term)» foi ignorada: depois de limpa, não sobrou nada.",
                    "The word “\(note.term)” was skipped: nothing was left after cleanup."))
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
                tr("\(newNotes.count) новых слов — это много для одной очереди. "
                    + "Лимит новых карточек в день всё сгладит, но набор лучше дробить.",
                   "\(newNotes.count) palavras novas é muito para uma fila. "
                    + "O limite diário de cartões novos suaviza tudo, mas é melhor dividir.",
                   "\(newNotes.count) new words is a lot for one queue. "
                    + "The daily limit of new cards will smooth it out, but splitting is better."))
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
