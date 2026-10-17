import Foundation
import SwiftData
import Observation
import AJFMCore

/// Состояние экрана облачного бэкапа: включение, отправка, список снимков,
/// восстановление. База приходит параметром — модель живёт в `@State`
/// экрана, а контекст из окружения доступен только в `body`.
@Observable
@MainActor
final class CloudBackupViewModel {
    var enabled = CloudBackupService.isEnabled
    private(set) var list: CloudBackupList?
    private(set) var busy = false
    private(set) var status: String?
    private(set) var error: String?
    var confirmErase = false
    private(set) var pendingRestore: PendingCloudRestore?
    private(set) var restored: RestoreService.Result?

    var isAvailable: Bool { RecapBackend.isConfigured }
    var entries: [CloudBackupEntry] { list?.backups ?? [] }
    /// Сколько снимков хранит сервер; пока список не пришёл — как по умолчанию.
    var keep: Int { list?.keep ?? 7 }
    var showsSignInHint: Bool { list?.signedIn == false }

    /// Для алертов: закрытие алерта — отказ от восстановления.
    var isRestorePending: Bool {
        get { pendingRestore != nil }
        set { if !newValue { pendingRestore = nil } }
    }

    var isShowingRestored: Bool {
        get { restored != nil }
        set { if !newValue { restored = nil } }
    }

    // MARK: - Действия

    func enabledChanged(_ on: Bool, in context: ModelContext) {
        CloudBackupService.isEnabled = on
        // Включил — первая копия сразу, а не завтра.
        if on { uploadNow(in: context) }
    }

    func uploadNow(in context: ModelContext) {
        let service = CloudBackupService(context: context)
        perform(in: context) { try await service.upload() }
    }

    func eraseAll(in context: ModelContext) {
        let service = CloudBackupService(context: context)
        perform(in: context) { try await service.eraseAll() }
    }

    func refresh(in context: ModelContext) async {
        guard isAvailable else { return }
        do {
            list = try await CloudBackupService(context: context).list()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func prepareRestore(_ entry: CloudBackupEntry, in context: ModelContext) {
        busy = true
        error = nil
        Task {
            do {
                let data = try await CloudBackupService(context: context).download(entry)
                let (backup, preview) = try RestoreService(context: context).preview(from: data)
                pendingRestore = PendingCloudRestore(backup: backup, preview: preview)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    /// Снимок — из алерта (`presenting:`), а не из свойства: закрытие алерта
    /// могло обнулить его раньше, чем сработала кнопка.
    func restore(_ pending: PendingCloudRestore, in context: ModelContext) {
        pendingRestore = nil
        do {
            let result = try RestoreService(context: context).restore(pending.backup)
            // Показ итога — следующим циклом: алерт, поднятый в том же проходе,
            // что и закрытие предыдущего, теряется.
            Task { @MainActor in restored = result }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func perform(in context: ModelContext, _ action: @escaping () async throws -> Void) {
        busy = true
        error = nil
        status = nil
        Task {
            do {
                try await action()
                status = tr("Готово", "Feito", "Done")
                await refresh(in: context)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

struct PendingCloudRestore: Identifiable {
    let id = UUID()
    let backup: BackupFile
    let preview: RestoreService.Preview
}
