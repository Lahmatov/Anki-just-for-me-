import Foundation
import SwiftData
import AJFMCore

/// Автоматический бэкап базы.
///
/// Синхронизации между устройствами нет (для неё нужен платный аккаунт),
/// поэтому единственная страховка от потери прогресса — файл. Раз в неделю
/// он пишется сам, чтобы не зависеть от того, вспомнил ли ты нажать кнопку.
@MainActor
struct BackupService {
    let context: ModelContext

    static let interval: TimeInterval = 7 * 86_400

    /// Папка бэкапов в документах приложения — она видна в «Файлах»,
    /// откуда файл можно забрать или положить в iCloud Drive.
    static var directory: URL? {
        let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first
        guard let folder = documents?.appendingPathComponent("Backups") else { return nil }
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Делает бэкап, если прошла неделя с прошлого.
    @discardableResult
    func backupIfNeeded(now: Date = Date()) -> URL? {
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: SettingsKey.lastBackupDate) as? Date
        if let last, now.timeIntervalSince(last) < Self.interval { return nil }
        return performBackup(now: now)
    }

    @discardableResult
    func performBackup(now: Date = Date()) -> URL? {
        guard let directory = Self.directory else {
            Log.error(.backup, "Не нашлась папка для бэкапов")
            return nil
        }
        guard let data = try? BackupCoder.encode(
            try ExportService(context: context).makeBackup()) else {
            Log.error(.backup, "Не удалось собрать бэкап")
            return nil
        }

        let stamp = Self.stampFormatter.string(from: now)
        let url = directory.appendingPathComponent("ajfm-\(stamp).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }

        UserDefaults.standard.set(now, forKey: SettingsKey.lastBackupDate)
        pruneOldBackups(in: directory)
        Log.info(
            .backup, "Бэкап сохранён",
            detail: "\(url.lastPathComponent), \(data.count / 1024) КБ")
        return url
    }

    /// Храним последние восемь файлов — примерно два месяца истории.
    private func pruneOldBackups(in directory: URL, keep: Int = 8) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let sorted = files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in sorted.dropFirst(keep) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: SettingsKey.lastBackupDate) as? Date
    }

    var backupCount: Int {
        guard let directory = Self.directory else { return 0 }
        let files = (try? FileManager.default.contentsOfDirectory(
            atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.count
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
