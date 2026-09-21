import Foundation

/// Полный бэкап базы: все наборы со словами и состоянием карточек.
///
/// Синхронизации между устройствами нет (для неё нужен платный аккаунт Apple),
/// поэтому это единственная страховка от потери прогресса. См. docs/decisions.md.
public struct BackupFile: Codable, Equatable, Sendable {
    public static let formatID = "ajfm-backup"
    public static let supportedVersion = 1

    public var format: String
    public var version: Int
    public var exportedAt: Date
    public var decks: [BackupDeck]

    public init(exportedAt: Date, decks: [BackupDeck]) {
        self.format = Self.formatID
        self.version = Self.supportedVersion
        self.exportedAt = exportedAt
        self.decks = decks
    }

    public var noteCount: Int { decks.reduce(0) { $0 + $1.notes.count } }
}

public struct BackupDeck: Codable, Equatable, Sendable {
    public var name: String
    public var folder: String?
    public var scheduler: SchedulerID
    public var cardTypes: [CardType]
    public var source: String?
    public var createdAt: Date
    public var notes: [BackupNote]

    public init(
        name: String, folder: String?, scheduler: SchedulerID, cardTypes: [CardType],
        source: String?, createdAt: Date, notes: [BackupNote]
    ) {
        self.name = name
        self.folder = folder
        self.scheduler = scheduler
        self.cardTypes = cardTypes
        self.source = source
        self.createdAt = createdAt
        self.notes = notes
    }
}

public struct BackupNote: Codable, Equatable, Sendable {
    public var data: NoteData
    public var createdAt: Date
    public var cards: [BackupCard]

    public init(data: NoteData, createdAt: Date, cards: [BackupCard]) {
        self.data = data
        self.createdAt = createdAt
        self.cards = cards
    }
}

public struct BackupCard: Codable, Equatable, Sendable {
    public var type: CardType
    public var due: Date
    public var intervalDays: Double
    public var reps: Int
    public var lapses: Int
    public var state: String
    /// Состояние конкретного алгоритма, как он сам его сериализовал.
    public var schedulerState: String?

    public init(
        type: CardType, due: Date, intervalDays: Double, reps: Int, lapses: Int,
        state: String, schedulerState: String?
    ) {
        self.type = type
        self.due = due
        self.intervalDays = intervalDays
        self.reps = reps
        self.lapses = lapses
        self.state = state
        self.schedulerState = schedulerState
    }
}

public enum BackupCoder {
    public static func encode(_ backup: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    public static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data)
    }
}
