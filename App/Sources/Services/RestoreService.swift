import Foundation
import SwiftData
import AJFMCore

/// Восстановление базы из бэкапа.
///
/// Без этого бэкап бесполезен: файл пишется, но вернуть из него ничего нельзя.
/// А поскольку синхронизации между устройствами нет, это единственный путь
/// перенести прогресс — на новый телефон или после переустановки.
@MainActor
struct RestoreService {
    let context: ModelContext

    struct Preview: Equatable {
        var decks: Int
        var notes: Int
        var cards: Int
        var exportedAt: Date
        var matureWords: Int
    }

    struct Result: Equatable {
        var decks: Int
        var notes: Int
        var cards: Int
    }

    /// Разбирает файл и описывает, что в нём, не трогая базу.
    func preview(from data: Data) throws -> (BackupFile, Preview) {
        let backup = try BackupCoder.decode(data)
        let cards = backup.decks.flatMap { $0.notes.flatMap(\.cards) }
        return (backup, Preview(
            decks: backup.decks.count,
            notes: backup.noteCount,
            cards: cards.count,
            exportedAt: backup.exportedAt,
            matureWords: cards.filter { $0.review.isMature }.count))
    }

    /// Заменяет содержимое базы данными из бэкапа.
    ///
    /// Именно заменяет, а не дополняет: восстановление должно возвращать
    /// ровно то состояние, которое было на момент бэкапа, иначе прогресс
    /// карточек сливался бы непредсказуемо.
    @discardableResult
    func restore(_ backup: BackupFile) throws -> Result {
        var cardCount = 0

        // Чистка, наполнение и сохранение — одна транзакция под одним откатом.
        // Любой сбой внутри обязан вернуть базу в исходное состояние: иначе
        // удаления останутся висеть в общем контексте, и первое же постороннее
        // сохранение сотрёт библиотеку уже после того, как восстановление
        // сообщило об ошибке.
        do {
            try wipe()

            var folderCache: [String: Folder] = [:]
            for backupDeck in backup.decks {
                let deck = Deck(
                    name: backupDeck.name,
                    scheduler: backupDeck.scheduler,
                    cardTypes: backupDeck.cardTypes,
                    source: backupDeck.source)
                context.insert(deck)
                deck.createdAt = backupDeck.createdAt
                deck.folder = folder(for: backupDeck.folder, cache: &folderCache)

                for backupNote in backupDeck.notes {
                    let note = Note(data: backupNote.data)
                    context.insert(note)
                    note.createdAt = backupNote.createdAt
                    note.deck = deck

                    for backupCard in backupNote.cards {
                        let card = Card(type: backupCard.type)
                        context.insert(card)
                        card.note = note
                        card.reviewState = backupCard.review
                        cardCount += 1
                    }
                }
            }

            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        return Result(
            decks: backup.decks.count, notes: backup.noteCount, cards: cardCount)
    }

    /// Создаёт цепочку папок по пути, переиспользуя уже созданные.
    private func folder(for path: String?, cache: inout [String: Folder]) -> Folder? {
        let parts = (path ?? "")
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        var parent: Folder?
        var walked: [String] = []
        for name in parts {
            walked.append(name)
            let key = walked.joined(separator: "/")
            if let existing = cache[key] {
                parent = existing
                continue
            }
            let folder = Folder(name: name)
            context.insert(folder)
            folder.parent = parent
            cache[key] = folder
            parent = folder
        }
        return parent
    }

    /// Чистит всё, что восстанавливается из бэкапа. История пересказов,
    /// расходы, награды и журнал занятий не трогаются — бэкап их не содержит,
    /// а терять счёт учебных дней при переносе на новый телефон обидно.
    private func wipe() throws {
        // Ошибку выборки нельзя глотать: «ничего не нашлось» превратило бы
        // замену в слияние, о котором пользователю не сказали.
        for folder in try context.fetch(FetchDescriptor<Folder>()) {
            context.delete(folder)
        }
        for deck in try context.fetch(FetchDescriptor<Deck>()) {
            context.delete(deck)
        }
        for note in try context.fetch(FetchDescriptor<Note>()) {
            context.delete(note)
        }
        for card in try context.fetch(FetchDescriptor<Card>()) {
            context.delete(card)
        }
    }
}
