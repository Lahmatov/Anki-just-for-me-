import Foundation
import SwiftData
import UIKit
import Observation
import AJFMCore

/// Форма обращения в поддержку (P-72).
@Observable
@MainActor
final class SupportTicketViewModel {
    var category: SupportCategory = .question
    var message = ""
    var contact = ""
    var attachDiagnostics = true
    private(set) var sending = false
    private(set) var sent: BackendAPI.SupportTicket?
    private(set) var error: String?
    /// Считается один раз при открытии: раньше каждый проход `body` заново
    /// считал карточки в базе.
    private(set) var diagnostics: [String: String] = [:]

    var ticket: BackendAPI.SupportTicketBody {
        BackendAPI.SupportTicketBody(category: category, message: message, contact: contact,
                                     diagnostics: attachDiagnostics ? diagnostics : nil)
    }

    var canSend: Bool { ticket.isValid && !sending }

    /// Что уйдёт с обращением — показывается человеку под переключателем.
    var diagnosticsSummary: String {
        diagnostics.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " · ")
    }

    func loadDiagnostics(in context: ModelContext) {
        diagnostics = SupportDiagnostics.make(
            appVersion: AccountView.version, systemVersion: UIDevice.current.systemVersion,
            device: UIDevice.current.model, language: Loc.language,
            studyLanguage: StudyLanguageStore.storedCurrent,
            cards: try? context.fetchCount(FetchDescriptor<Card>()))
            // Сводка сбоев за месяц от MetricKit — без стека и адресов (P-74).
            .merging(DiagnosticsService.summary) { current, _ in current }
    }

    func send() async {
        sending = true
        error = nil
        defer { sending = false }
        do {
            sent = try await RecapBackend.shared.support(ticket)
            AnalyticsService.track(.supportSent(category: category))
            Haptics.success()
        } catch {
            Log.failure(.network, "Обращение в поддержку не ушло", error)
            self.error = error.localizedDescription
        }
    }
}
