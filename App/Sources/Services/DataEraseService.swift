import Foundation
import SwiftData
import AJFMCore

/// «Удалить все данные» — одной кнопкой, как требуют правила App Store
/// для приложений, которые что-то хранят о человеке.
///
/// Всё, что приложение накопило, уходит целиком: слова, историю повторов,
/// пересказы, цели, расходы, ключи в Keychain, настройки, профиль с фото
/// и локальные бэкапы. Сетевое — аккаунт и устройство на сервере, облачные
/// снимки — удаляет экран до этого: это может не получиться, и тогда
/// локальное лучше не трогать.
@MainActor
struct DataEraseService {
    let context: ModelContext

    /// Удаляет содержимое базы. Сначала зависимые записи, потом те,
    /// на которые они ссылаются: так правила удаления связей не мешают.
    func eraseDatabase() throws {
        try deleteAll(Review.self)
        try deleteAll(Card.self)
        try deleteAll(Note.self)
        try deleteAll(Deck.self)
        try deleteAll(Folder.self)
        try deleteAll(RetellSession.self)
        try deleteAll(UsageEntry.self)
        try deleteAll(RewardContractEntity.self)
        try deleteAll(ProgressSnapshot.self)
        try deleteAll(TrackedShow.self)
        try context.save()
    }

    private func deleteAll<Model: PersistentModel>(_ type: Model.Type) throws {
        for object in try context.fetch(FetchDescriptor<Model>()) {
            context.delete(object)
        }
    }

    /// Ключи API и строка подключения к облаку.
    static func eraseSecrets() {
        Keychain.remove(Keychain.claudeAPIKey)
        Keychain.remove(Keychain.neonConnection)
        Keychain.remove(Keychain.recapDeviceToken)
    }

    /// Все настройки приложения — как после установки.
    static func eraseSettings(defaults: UserDefaults = .standard,
                              domain: String? = Bundle.main.bundleIdentifier) {
        if let domain { defaults.removePersistentDomain(forName: domain) }
        // Язык интерфейса живёт и в памяти — возвращаем системный.
        Loc.language = AppLanguage.resolve(preferred: Locale.preferredLanguages)
    }

    /// Недельные бэкапы в «Файлах».
    static func eraseLocalBackups(fileManager: FileManager = .default) {
        guard let directory = BackupService.directory,
              let files = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files { try? fileManager.removeItem(at: file) }
    }

    /// Всё локальное разом. Журнал очищается, и в нём остаётся одна запись —
    /// о том, что данные удалены.
    func eraseEverythingLocal() throws {
        try eraseDatabase()
        Self.eraseSecrets()
        Self.eraseLocalBackups()
        // Фото профиля — файл, а не настройка: само с UserDefaults не уйдёт.
        ProfileStore.eraseLocal()
        Self.eraseSettings()
        ProfileStore.shared.reload()
        RecapAccount.shared.forgetLocalState()
        // Журнал на экране хранит названия наборов и слова из ошибок.
        EventLog.shared.clear()
        Log.info(.app, "Все данные удалены")
    }
}
