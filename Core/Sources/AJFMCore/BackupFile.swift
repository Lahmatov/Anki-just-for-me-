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
    /// Состояние повторений целиком — интервал, устойчивость, коробка и прочее.
    /// Ради этого бэкап и существует: слова восстановить легко, прогресс — нет.
    public var review: ReviewState

    public init(type: CardType, review: ReviewState) {
        self.type = type
        self.review = review
    }
}

public enum BackupError: Error, Equatable, LocalizedError {
    case wrongFormat(found: String)
    case notABackup
    case unsupportedVersion(found: Int, supported: Int)

    public var errorDescription: String? {
        switch self {
        case .wrongFormat(let found):
            return "Это не бэкап, а «\(found)». Восстанавливать из него нечего."
        case .notABackup:
            return "Это не файл бэкапа: в нём нет поля формата."
        case .unsupportedVersion(let found, let supported):
            return "Бэкап версии \(found) новее поддерживаемой (\(supported))."
        }
    }
}

/// Только формат и версия — читается до полного разбора.
private struct BackupEnvelope: Decodable {
    var format: String?
    var version: Int?
}

public enum BackupCoder {
    public static func encode(_ backup: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    public static func decode(_ data: Data) throws -> BackupFile {
        // Восстановление заменяет базу целиком, поэтому формат проверяется
        // строже, чем при обычном импорте, и до всего остального: иначе
        // на чужом файле мы бы сообщили о пропавшем поле вместо внятного
        // «это не бэкап».
        // Проверяем ещё до полного разбора, иначе на чужом файле пользователь
        // увидит системное «не удалось прочитать данные» вместо объяснения.
        // Массив или число на верхнем уровне — тоже не бэкап: JSON со списком
        // слов приложение принимает при обычном импорте, и спутать легко.
        guard let envelope = try? JSONDecoder().decode(BackupEnvelope.self, from: data),
              let format = envelope.format else {
            throw BackupError.notABackup
        }
        guard format == BackupFile.formatID else {
            throw BackupError.wrongFormat(found: format)
        }
        if let version = envelope.version, version > BackupFile.supportedVersion {
            throw BackupError.unsupportedVersion(
                found: version, supported: BackupFile.supportedVersion)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data)
    }
}
