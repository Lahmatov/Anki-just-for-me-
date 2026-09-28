import Foundation
import SwiftData
import AJFMCore

/// Бэкап базы в Neon — бесплатный облачный Postgres.
///
/// Зачем: локальный бэкап лежит на том же телефоне, что и база, и погибает
/// вместе с ним. Синхронизация через iCloud требует платного аккаунта
/// разработчика, а Neon — нет: бесплатного тарифа хватает с запасом.
///
/// Источник правды — база на телефоне. В облако раз в сутки уходит снимок,
/// из которого можно восстановиться на новом телефоне. Строка подключения
/// (в ней пароль) живёт только в Keychain и никогда не пишется в журнал.
@MainActor
struct CloudBackupService {
    let context: ModelContext

    static var connection: NeonConnection? {
        guard let raw = Keychain.get(Keychain.neonConnection), !raw.isEmpty else { return nil }
        return try? NeonConnection(connectionString: raw)
    }

    static var isConfigured: Bool { connection != nil }

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

    private func client() throws -> NeonClient {
        guard let connection = Self.connection else { throw NeonError.invalidConnectionString }
        return NeonClient(connection: connection)
    }

    /// Подключение: проверяет базу (заодно создаёт таблицу) и только после
    /// этого сохраняет строку. Сохранить непроверенную — значит показать
    /// «подключено», когда каждая отправка молча падает.
    func connect(_ connection: NeonConnection) async throws {
        _ = try await NeonClient(connection: connection).run(CloudBackupSQL.createTable)
        Keychain.set(connection.connectionString, for: Keychain.neonConnection)
        Log.info(.backup, "Neon подключён", detail: connection.redacted)
    }

    /// Удаляет все снимки из облака — часть «Удалить все данные».
    func eraseAll() async throws {
        _ = try await client().run(CloudBackupSQL.dropAll)
        Log.info(.backup, "Снимки в Neon удалены")
    }

    /// Отправляет снимок, если с прошлого прошли сутки.
    func uploadIfNeeded(now: Date = Date()) async {
        guard Self.isConfigured, CloudBackupSQL.isDue(lastUpload: Self.lastUpload, now: now) else {
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

    /// Снимок базы в облако: таблица, запись и чистка старых — одной транзакцией.
    func upload(now: Date = Date()) async throws {
        // Выборка из базы — на главном потоке (так требует SwiftData),
        // а кодирование многомегабайтного снимка — нет: иначе интерфейс
        // подвисал бы при первом запуске за день.
        let backup = try ExportService(context: context).makeBackup()
        let (data, payload) = try await Self.encode(backup)
        let mature = backup.decks
            .flatMap { $0.notes }
            .filter { note in note.cards.contains { $0.review.isMature } }
            .count

        _ = try await client().run([
            CloudBackupSQL.createTable,
            CloudBackupSQL.insert(
                device: Self.deviceLabel, noteCount: backup.noteCount,
                matureWords: mature, payload: payload),
            CloudBackupSQL.prune(),
        ])
        UserDefaults.standard.set(now, forKey: SettingsKey.lastCloudBackupDate)
        Log.info(.backup, "Бэкап отправлен в Neon",
                 detail: "слов: \(backup.noteCount), \(data.count / 1024) КБ")
    }

    nonisolated private static func encode(_ backup: BackupFile) async throws -> (Data, String) {
        let data = try BackupCoder.encode(backup)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw NeonError.badResponse
        }
        return (data, payload)
    }

    func list() async throws -> [CloudBackupEntry] {
        let results = try await client().run([CloudBackupSQL.createTable, CloudBackupSQL.list()])
        guard let last = results.last else { return [] }
        return CloudBackupSQL.parseList(last)
    }

    /// Снимок как файл бэкапа — дальше обычный путь восстановления.
    func download(_ entry: CloudBackupEntry) async throws -> Data {
        let result = try await client().run(CloudBackupSQL.fetch(id: entry.id))
        guard let payload = result.value("payload", row: 0) else { throw NeonError.badResponse }
        return Data(payload.utf8)
    }
}
