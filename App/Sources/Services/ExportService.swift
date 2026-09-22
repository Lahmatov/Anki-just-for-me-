import Foundation
import SwiftData
import AJFMCore

/// Экспорт в JSON. Синхронизации между устройствами нет, поэтому это
/// единственная страховка от потери прогресса — решение P-6 в docs/decisions.md.
@MainActor
struct ExportService {
    let context: ModelContext

    /// Полный бэкап базы: наборы, слова и состояние карточек.
    func makeBackup() throws -> BackupFile {
        let decks = try context.fetch(FetchDescriptor<Deck>(
            sortBy: [SortDescriptor(\Deck.createdAt)]))

        let backupDecks = decks.map { deck in
            BackupDeck(
                name: deck.name,
                folder: deck.folder?.path,
                scheduler: deck.scheduler,
                cardTypes: deck.cardTypes,
                source: deck.source,
                createdAt: deck.createdAt,
                notes: deck.notes
                    .sorted { $0.createdAt < $1.createdAt }
                    .map { note in
                        BackupNote(
                            data: note.asNoteData,
                            createdAt: note.createdAt,
                            cards: note.cards.map { card in
                                BackupCard(type: card.type, review: card.reviewState)
                            }
                        )
                    }
            )
        }

        return BackupFile(exportedAt: Date(), decks: backupDecks)
    }

    /// Пишет бэкап во временный файл и возвращает путь — для кнопки «Поделиться».
    func writeBackupFile() throws -> URL {
        let data = try BackupCoder.encode(try makeBackup())
        let stamp = Self.fileStampFormatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ajfm-backup-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Один набор в формате `ajfm-deck` — им можно поделиться или вернуть его мне.
    func writeDeckFile(_ deck: Deck) throws -> URL {
        let file = DeckFile(
            deck: DeckMeta(
                name: deck.name,
                folder: deck.folder?.path,
                language: "en-US",
                scheduler: deck.scheduler,
                cardTypes: deck.cardTypes,
                source: deck.source
            ),
            notes: deck.notes
                .sorted { $0.createdAt < $1.createdAt }
                .map(\.asNoteData)
        )
        let data = try DeckParser.encode(file)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.safeFileName(deck.name)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func safeFileName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "deck" : cleaned
    }

    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
