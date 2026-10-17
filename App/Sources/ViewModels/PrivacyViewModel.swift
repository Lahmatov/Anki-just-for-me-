import Foundation
import SwiftData
import Observation
import AJFMCore

/// «Удалить все данные» и согласие на ИИ — логика экрана конфиденциальности.
@Observable
@MainActor
final class PrivacyViewModel {
    var confirmErase = false
    var eraseCloud = true
    var aiConsent = AIConsent.isGiven
    private(set) var erasing = false
    var erased = false
    private(set) var eraseError: String?

    var serverAvailable: Bool { RecapBackend.isConfigured }

    var isShowingError: Bool {
        get { eraseError != nil }
        set { if !newValue { eraseError = nil } }
    }

    func aiConsentChanged(_ value: Bool) {
        AIConsent.isGiven = value
    }

    /// Порядок важен: облако и сервер — до локальных данных, потому что
    /// без токена устройства их там уже не найти. Не вышло на сервере —
    /// телефон не трогаем, чтобы человек мог повторить.
    func erase(in context: ModelContext) async {
        erasing = true
        defer { erasing = false }
        if eraseCloud, serverAvailable {
            do {
                try await CloudBackupService(context: context).eraseAll()
            } catch {
                Log.failure(.backup, "Снимки в облаке не удалились", error)
                eraseError = tr("Копии в облаке не удалились: \(error.localizedDescription). "
                                    + "Локальные данные не тронуты — попробуй ещё раз.",
                                "As cópias na nuvem não foram apagadas: \(error.localizedDescription). "
                                    + "Os dados locais estão intactos — tenta de novo.",
                                "Cloud copies weren't deleted: \(error.localizedDescription). "
                                    + "Local data is untouched — try again.")
                return
            }
        }
        // Сначала аккаунт (с отзывом входа у Apple), потом само устройство.
        if serverAvailable {
            do {
                try await RecapAccount.shared.deleteAccountIfSignedIn()
                try await RecapBackend.shared.forgetDevice()
            } catch {
                Log.failure(.network, "Устройство на сервере Recap не удалилось", error)
                eraseError = tr("Данные на сервере Recap не удалились: \(error.localizedDescription). "
                                    + "Локальные данные не тронуты — попробуй ещё раз.",
                                "Os dados no servidor Recap não foram apagados: \(error.localizedDescription). "
                                    + "Os dados locais estão intactos — tenta de novo.",
                                "Recap server data wasn't deleted: \(error.localizedDescription). "
                                    + "Local data is untouched — try again.")
                return
            }
        }
        do {
            try DataEraseService(context: context).eraseEverythingLocal()
            Haptics.success()
            erased = true
        } catch {
            Log.failure(.app, "Данные не удалились", error)
            eraseError = error.localizedDescription
        }
    }
}
