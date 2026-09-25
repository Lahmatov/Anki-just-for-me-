import Foundation
import SwiftData
import AJFMCore

struct ImportResult {
    var deckName: String
    var addedNotes: Int
    var addedCards: Int
    var skippedDuplicates: Int
}

@MainActor
struct ImportService {
    let context: ModelContext

    /// Разбирает файл и строит план, не трогая базу.
    func makePlan(from data: Data) throws -> ImportPlan {
        let file = try DeckParser.parse(data: data)
        return ImportPlanner.plan(file: file, existingTerms: try existingTerms())
    }

    func makePlan(from text: String) throws -> ImportPlan {
        let file = try DeckParser.parse(string: text)
        return ImportPlanner.plan(file: file, existingTerms: try existingTerms())
    }

    func makePlan(from file: DeckFile) throws -> ImportPlan {
        ImportPlanner.plan(file: file, existingTerms: try existingTerms())
    }

    /// Недавно добавленные слова — первыми: именно их модели важнее всего
    /// не повторить в новом наборе.
    func recentTerms(limit: Int) -> [String] {
        var descriptor = FetchDescriptor<Note>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).map(\.term)
    }

    /// Нормализованный термин → название набора, где он уже лежит.
    /// Слов в личной базе тысячи, так что читаем всё разом и сравниваем в памяти.
    private func existingTerms() throws -> [String: String] {
        let notes = try context.fetch(FetchDescriptor<Note>())
        var map: [String: String] = [:]
        for note in notes where map[note.normalizedTerm] == nil {
            map[note.normalizedTerm] = note.deck?.name ?? "без набора"
        }
        return map
    }

    /// Записывает план в базу. `includeDuplicates` добавляет и те слова,
    /// что уже есть в других наборах.
    @discardableResult
    func apply(_ plan: ImportPlan, includeDuplicates: Bool = false) throws -> ImportResult {
        let folder = try resolveFolder(path: plan.folderPath)
        let deck = Deck(
            name: plan.deckName,
            scheduler: plan.scheduler,
            cardTypes: plan.cardTypes,
            source: plan.source
        )
        context.insert(deck)
        deck.folder = folder

        var notesToAdd = plan.newNotes
        if includeDuplicates {
            // Дубли внутри самого файла добавлять не имеет смысла ни при каком флаге.
            notesToAdd += plan.duplicates
                .filter { $0.existingDeckName != nil }
                .map(\.note)
        }

        var addedCards = 0
        for data in notesToAdd {
            // SwiftData надёжнее связывает объекты, когда они уже вставлены
            // в контекст, поэтому отношение проставляется после insert.
            let note = Note(data: data)
            context.insert(note)
            note.deck = deck

            for type in plan.cardTypes {
                // Карточка с пропуском бессмысленна без самого пропуска.
                if type == .cloze, (data.cloze ?? "").isEmpty { continue }
                let card = Card(type: type)
                context.insert(card)
                card.note = note
                addedCards += 1
            }
        }

        try context.save()

        Log.info(
            .importing, "Набор «\(plan.deckName)» добавлен",
            detail: "слов: \(notesToAdd.count), карточек: \(addedCards), "
                + "дублей пропущено: \(plan.duplicates.count)")

        return ImportResult(
            deckName: plan.deckName,
            addedNotes: notesToAdd.count,
            addedCards: addedCards,
            skippedDuplicates: plan.duplicates.count - (notesToAdd.count - plan.newNotes.count)
        )
    }

    /// Находит или создаёт цепочку папок по пути вида ["Сериалы", "Breaking Bad"].
    private func resolveFolder(path: [String]) throws -> Folder? {
        guard !path.isEmpty else { return nil }
        let allFolders = try context.fetch(FetchDescriptor<Folder>())
        var parent: Folder?

        for name in path {
            let existing = allFolders.first {
                $0.name == name && $0.parent?.persistentModelID == parent?.persistentModelID
            }
            if let existing {
                parent = existing
            } else {
                let folder = Folder(name: name)
                context.insert(folder)
                folder.parent = parent
                parent = folder
            }
        }
        return parent
    }
}
