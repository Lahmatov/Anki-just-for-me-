import Foundation

/// Бэкап в облачной базе.
public struct CloudBackupEntry: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var device: String
    public var createdAt: Date
    public var noteCount: Int
    public var matureWords: Int
    public var bytes: Int

    public init(
        id: Int64, device: String, createdAt: Date, noteCount: Int, matureWords: Int, bytes: Int
    ) {
        self.id = id
        self.device = device
        self.createdAt = createdAt
        self.noteCount = noteCount
        self.matureWords = matureWords
        self.bytes = bytes
    }
}

/// Запросы облачного бэкапа.
///
/// Схема намеренно простая: одна таблица снимков базы, а не построчная
/// синхронизация. Источник правды — база на телефоне; облако хранит её
/// копии, из которых можно восстановиться на новом телефоне. Построчная
/// синхронизация двух устройств — это разрешение конфликтов, а для одного
/// человека с одним айфоном она не нужна.
///
/// Снимок хранится текстом, а не `jsonb`: jsonb переставляет ключи и
/// нормализует числа, а восстановление должно получить ровно то, что
/// было отправлено.
public enum CloudBackupSQL {
    public static let table = "ajfm_backups"
    /// Сколько снимков хранить. Бесплатный Neon даёт 0.5 ГБ — с запасом
    /// на годы, но копить неограниченно всё равно незачем.
    public static let keep = 20

    public static let createTable = NeonQuery("""
        CREATE TABLE IF NOT EXISTS \(table) (
            id bigserial PRIMARY KEY,
            device text NOT NULL,
            created_at timestamptz NOT NULL DEFAULT now(),
            note_count integer NOT NULL,
            mature_words integer NOT NULL,
            payload text NOT NULL
        )
        """)

    public static func insert(
        device: String, noteCount: Int, matureWords: Int, payload: String
    ) -> NeonQuery {
        NeonQuery(
            "INSERT INTO \(table) (device, note_count, mature_words, payload) "
                + "VALUES ($1, $2::integer, $3::integer, $4) RETURNING id",
            [.text(device), .int(noteCount), .int(matureWords), .text(payload)])
    }

    /// Старые снимки удаляются тем же вызовом, что и запись нового.
    public static func prune(keep: Int = keep) -> NeonQuery {
        NeonQuery(
            "DELETE FROM \(table) WHERE id NOT IN "
                + "(SELECT id FROM \(table) ORDER BY created_at DESC, id DESC LIMIT $1::integer)",
            [.int(max(1, keep))])
    }

    /// Список без самих снимков: они тяжёлые, а для выбора нужен только размер.
    public static func list(limit: Int = keep) -> NeonQuery {
        NeonQuery(
            "SELECT id, device, floor(extract(epoch FROM created_at))::bigint AS created, "
                + "note_count, mature_words, octet_length(payload) AS bytes "
                + "FROM \(table) ORDER BY created_at DESC, id DESC LIMIT $1::integer",
            [.int(max(1, limit))])
    }

    public static func fetch(id: Int64) -> NeonQuery {
        NeonQuery("SELECT payload FROM \(table) WHERE id = $1::bigint", [.text(String(id))])
    }

    public static func parseList(_ result: NeonResult) -> [CloudBackupEntry] {
        result.rows.indices.compactMap { row in
            guard let id = result.value("id", row: row).flatMap(Int64.init),
                  let created = result.value("created", row: row).flatMap(Double.init) else {
                return nil
            }
            return CloudBackupEntry(
                id: id,
                device: result.value("device", row: row) ?? "",
                createdAt: Date(timeIntervalSince1970: created),
                noteCount: result.value("note_count", row: row).flatMap(Int.init) ?? 0,
                matureWords: result.value("mature_words", row: row).flatMap(Int.init) ?? 0,
                bytes: result.value("bytes", row: row).flatMap(Int.init) ?? 0)
        }
    }

    /// Пора ли отправить новый снимок: раз в сутки хватает — прогресс
    /// за день потерять не страшно, а трафик и место не тратятся зря.
    public static func isDue(lastUpload: Date?, now: Date = Date(),
                             interval: TimeInterval = 86_400) -> Bool {
        guard let lastUpload else { return true }
        return now.timeIntervalSince(lastUpload) >= interval || lastUpload > now
    }
}
