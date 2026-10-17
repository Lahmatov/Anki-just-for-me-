import Foundation
import Observation
import AJFMCore

/// «Мои обращения»: список с сервера.
@Observable
@MainActor
final class SupportTicketsViewModel {
    /// nil — ещё грузится.
    private(set) var tickets: [BackendAPI.SupportTicket]?
    private(set) var error: String?

    var isLoading: Bool { tickets == nil && error == nil }

    func load() async {
        do {
            tickets = try await RecapBackend.shared.supportTickets()
            error = nil
        } catch {
            self.error = error.localizedDescription
            if tickets == nil { tickets = [] }
        }
    }
}
