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
    /// Обложка набора — постер сериала, если он нашёлся.
    public var coverURL: String?

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
        let folderPath = ImportPlan.folderPath(from: file.deck.folder ?? "")

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
            coverURL: file.deck.cover,
            newNotes: newNotes,
            duplicates: duplicates,
            warnings: warnings
        )
    }
}

// MARK: - Правки в превью

extension ImportPlan {
    /// Путь папки из строки «Сериалы / Friends / Сезон 1»: пробелы вокруг
    /// частей и пустые части отбрасываются.
    public static func folderPath(from text: String) -> [String] {
        text.split(separator: "/")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }

    /// Путь папки строкой — для поля ввода в превью.
    public var folderText: String { folderPath.joined(separator: " / ") }

    /// План с правками из превью.
    ///
    /// Пустое название не принимается — остаётся прежнее: набор без имени
    /// в списке не найти. Без единого вида карточек набор был бы пустым,
    /// поэтому пустой выбор тоже не принимается. Порядок видов — как
    /// в `CardType.allCases`, а не в порядке нажатий.
    public func edited(
        name: String, folder: String, scheduler: SchedulerID, cardTypes: Set<CardType>
    ) -> ImportPlan {
        var plan = self
        let name = name.trimmed
        if !name.isEmpty { plan.deckName = name }
        plan.folderPath = Self.folderPath(from: folder)
        plan.scheduler = scheduler
        if !cardTypes.isEmpty {
            plan.cardTypes = CardType.allCases.filter(cardTypes.contains)
        }
        return plan
    }

    /// «43 слова × 2 вида = 86 карточек» — ответ на вопрос, откуда
    /// карточек вдвое больше, чем слов.
    public static func cardsExplanation(words: Int, types: Int) -> String {
        let words = max(0, words)
        let types = max(0, types)
        let kinds = trCount(types, ru: ("вид", "вида", "видов"),
                            pt: ("tipo", "tipos"), en: ("type", "types"))
        return Counted.words(words) + " × " + kinds + " = " + Counted.cards(words * types)
    }
}

extension CardType {
    /// Что происходит на карточке этого вида — для подсказки при выборе.
    public var explanation: String {
        switch self {
        case .recognition:
            return tr("Видишь английское слово — вспоминаешь перевод.",
                      "Vês a palavra em inglês e lembras-te da tradução.",
                      "You see the English word and recall its meaning.")
        case .recall:
            return tr("Видишь перевод — вспоминаешь английское слово. Труднее, но так слово "
                        + "появляется в речи.",
                      "Vês a tradução e lembras-te da palavra em inglês. Mais difícil, mas é "
                        + "assim que ela aparece na fala.",
                      "You see the meaning and recall the English word. Harder, but that's how "
                        + "it gets into your speech.")
        case .listening:
            return tr("Слышишь слово — понимаешь, что это.", "Ouves a palavra e percebes o que é.",
                      "You hear the word and recognize it.")
        case .spelling:
            return tr("Слышишь слово — пишешь его по буквам.", "Ouves a palavra e escreves-a.",
                      "You hear the word and type it.")
        case .pronunciation:
            return tr("Произносишь слово вслух — приложение проверяет.",
                      "Dizes a palavra em voz alta e a aplicação verifica.",
                      "You say the word out loud and the app checks it.")
        case .cloze:
            return tr("Вставляешь слово в пропуск в примере.", "Completas a lacuna no exemplo.",
                      "You fill the word into the gap in an example.")
        }
    }
}

extension SchedulerID {
    /// Коротко — чем алгоритм отличается от остальных.
    public var explanation: String {
        switch self {
        case .fsrs6:
            return tr("Лучший выбор: сам подбирает интервалы под твою память.",
                      "A melhor escolha: ajusta os intervalos à tua memória.",
                      "Best choice: adapts the intervals to your memory.")
        case .sm2:
            return tr("Классика Anki: проверенная, но менее точная.",
                      "O clássico do Anki: provado, mas menos preciso.",
                      "The Anki classic: proven but less precise.")
        case .leitner:
            return tr("Пять коробок с фиксированными интервалами — просто и прозрачно.",
                      "Cinco caixas com intervalos fixos — simples e transparente.",
                      "Five boxes with fixed intervals — simple and transparent.")
        case .cram:
            return tr("Зубрёжка перед событием: всё сразу, без длинных интервалов.",
                      "Para marrar antes de um evento: tudo já, sem intervalos longos.",
                      "Cramming before an event: everything now, no long intervals.")
        }
    }
}
