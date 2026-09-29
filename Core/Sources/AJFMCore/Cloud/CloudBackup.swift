import Foundation

/// Снимок в облаке — строка списка с сервера Recap (`GET /v1/backups`).
public struct CloudBackupEntry: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var device: String
    public var createdAt: Date
    public var noteCount: Int
    public var matureWords: Int
    public var bytes: Int

    public init(
        id: String, device: String, createdAt: Date, noteCount: Int, matureWords: Int, bytes: Int
    ) {
        self.id = id
        self.device = device
        self.createdAt = createdAt
        self.noteCount = noteCount
        self.matureWords = matureWords
        self.bytes = bytes
    }

    private enum CodingKeys: String, CodingKey {
        case id, device, createdAt, noteCount, matureWords, size
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        device = try container.decodeIfPresent(String.self, forKey: .device) ?? ""
        // Сервер отдаёт секунды Unix — без зависимости от стратегии декодера дат.
        createdAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .createdAt))
        noteCount = try container.decodeIfPresent(Int.self, forKey: .noteCount) ?? 0
        matureWords = try container.decodeIfPresent(Int.self, forKey: .matureWords) ?? 0
        bytes = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
    }
}

/// Ответ `GET /v1/backups`.
public struct CloudBackupList: Decodable, Equatable, Sendable {
    public var backups: [CloudBackupEntry]
    /// Сколько снимков держит сервер — показывается под кнопкой.
    public var keep: Int
    /// Вошёл ли человек через Apple: только тогда снимки видны с нового телефона.
    public var signedIn: Bool

    public init(backups: [CloudBackupEntry], keep: Int, signedIn: Bool) {
        self.backups = backups
        self.keep = keep
        self.signedIn = signedIn
    }
}

/// Правила облачного бэкапа, не зависящие от сети и SwiftData.
///
/// Схема — снимками, а не построчной синхронизацией: источник правды —
/// база на телефоне, облако хранит её копии для переезда на новый телефон.
/// Синхронизация двух устройств — это разрешение конфликтов, а одному
/// человеку с одним айфоном она не нужна.
public enum CloudBackup {
    /// Метка сжатого снимка. Без неё новое приложение не отличило бы сжатый
    /// снимок от несжатого, а старое — приняло бы сжатые байты за битый JSON.
    public static let magic = Data("RCB1".utf8)

    /// Пора ли отправить новый снимок: раз в сутки хватает — прогресс
    /// за день потерять не страшно, а трафик и место не тратятся зря.
    public static func isDue(lastUpload: Date?, now: Date = Date(),
                             interval: TimeInterval = 86_400) -> Bool {
        guard let lastUpload else { return true }
        // Часы переведены назад — иначе отправка встала бы до той даты.
        return now.timeIntervalSince(lastUpload) >= interval || lastUpload > now
    }

    /// Сжатые байты с меткой — то, что уходит на сервер.
    public static func wrap(compressed: Data) -> Data {
        magic + compressed
    }

    /// Что пришло с сервера: сжатое (с меткой) или простой JSON бэкапа.
    public enum Payload: Equatable, Sendable {
        case compressed(Data)
        case plain(Data)
    }

    public static func unwrap(_ data: Data) -> Payload {
        if data.count >= magic.count, data.prefix(magic.count) == magic {
            return .compressed(Data(data.dropFirst(magic.count)))
        }
        return .plain(data)
    }

    /// Описание снимка — в адресе запроса: тело занято самим снимком.
    public static func uploadQuery(device: String, noteCount: Int, matureWords: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "device", value: String(device.prefix(64))),
            URLQueryItem(name: "notes", value: String(max(0, noteCount))),
            URLQueryItem(name: "mature", value: String(max(0, matureWords))),
        ]
    }
}
