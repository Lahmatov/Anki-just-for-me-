import Foundation
import SwiftData
import AJFMCore

/// Облачный бэкап на сервере Recap — том же, что собирает наборы.
///
/// Зачем: локальный бэкап лежит на том же телефоне, что и база, и погибает
/// вместе с ним. iCloud требует платного аккаунта разработчика, а сторонняя
/// база (раньше — Neon) требовала от человека завести её и вставить строку
/// подключения. Свой сервер не требует ничего: включил — и копии идут.
///
/// Источник правды — база на телефоне. На сервер раз в сутки уходит сжатый
/// снимок; на сервере он шифруется. Чтобы найти снимки с нового телефона,
/// нужен вход через Apple — без него они привязаны к этому телефону.
@MainActor
struct CloudBackupService {
    let context: ModelContext
    private var backend: RecapBackend { .shared }

    /// Включено человеком и есть куда отправлять. По умолчанию выключено:
    /// отправлять словарь и прогресс на сервер без спроса нельзя.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKey.cloudBackupEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.cloudBackupEnabled) }
    }

    static var isConfigured: Bool { isEnabled && RecapBackend.isConfigured }

    static var lastUpload: Date? {
        UserDefaults.standard.object(forKey: SettingsKey.lastCloudBackupDate) as? Date
    }

    /// Устройство, с которого снимок: имя модели и короткий номер установки —
    /// чтобы отличить снимки старого телефона от нового.
    static var deviceLabel: String {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: SettingsKey.deviceID) ?? {
            let fresh = String(UUID().uuidString.prefix(4))
            defaults.set(fresh, forKey: SettingsKey.deviceID)
            return fresh
        }()
        return "iPhone · \(id)"
    }

    /// Удаляет все снимки с сервера — часть «Удалить все данные».
    func eraseAll() async throws {
        try await backend.eraseBackups()
        UserDefaults.standard.removeObject(forKey: SettingsKey.lastCloudBackupDate)
        Log.info(.backup, "Снимки в облаке удалены")
    }

    /// Отправляет снимок, если с прошлого прошли сутки.
    func uploadIfNeeded(now: Date = Date()) async {
        guard Self.isConfigured, CloudBackup.isDue(lastUpload: Self.lastUpload, now: now) else {
            return
        }
        do {
            try await upload(now: now)
        } catch {
            // Фоновая отправка не должна мешать учёбе: ошибка — в журнал,
            // следующая попытка — при следующем запуске.
            Log.failure(.backup, "Облачный бэкап не отправился", error)
        }
    }

    /// Снимок базы на сервер. Старые сервер чистит сам тем же запросом.
    func upload(now: Date = Date()) async throws {
        // Выборка из базы — на главном потоке (так требует SwiftData),
        // а кодирование и сжатие многомегабайтного снимка — нет: иначе
        // интерфейс подвисал бы при первом запуске за день.
        let backup = try ExportService(context: context).makeBackup()
        let (raw, payload) = try await Self.pack(backup)
        let mature = backup.decks
            .flatMap { $0.notes }
            .filter { note in note.cards.contains { $0.review.isMature } }
            .count

        _ = try await backend.uploadBackup(payload, query: CloudBackup.uploadQuery(
            device: Self.deviceLabel, noteCount: backup.noteCount, matureWords: mature))
        UserDefaults.standard.set(now, forKey: SettingsKey.lastCloudBackupDate)
        Log.info(.backup, "Бэкап отправлен в облако",
                 detail: "слов: \(backup.noteCount), \(raw / 1024) → \(payload.count / 1024) КБ")
    }

    /// JSON бэкапа, сжатый zlib: словарь сжимается в 5–8 раз, а снимок
    /// уходит каждый день — и по мобильной сети тоже.
    nonisolated static func pack(_ backup: BackupFile) async throws -> (raw: Int, payload: Data) {
        let data = try BackupCoder.encode(backup)
        let compressed = try (data as NSData).compressed(using: .zlib) as Data
        return (data.count, CloudBackup.wrap(compressed: compressed))
    }

    /// Обратное к `pack`: снимок с сервера → файл бэкапа для восстановления.
    nonisolated static func unpack(_ data: Data) throws -> Data {
        switch CloudBackup.unwrap(data) {
        case .plain(let json):
            return json
        case .compressed(let body):
            return try (body as NSData).decompressed(using: .zlib) as Data
        }
    }

    func list() async throws -> CloudBackupList {
        try await backend.backups()
    }

    /// Снимок как файл бэкапа — дальше обычный путь восстановления.
    func download(_ entry: CloudBackupEntry) async throws -> Data {
        let data = try await backend.downloadBackup(id: entry.id)
        return try Self.unpack(data)
    }
}
