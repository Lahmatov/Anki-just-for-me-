import ActivityKit
import Foundation
import AJFMCore

/// Запуск и обновление Live Activity сессии повторения.
///
/// Только локальные обновления, без push: работает и на бесплатном аккаунте.
/// Человек выключил Live Activities в настройках iOS — молча ничего не делаем.
@MainActor
final class SessionActivityController {
    private var activity: Activity<SessionActivityAttributes>?
    private var startedAt = Date()

    func start(deckName: String, total: Int) {
        guard activity == nil, total > 0, !UITesting.isActive,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        startedAt = Date()
        let attributes = SessionActivityAttributes(deckName: deckName, language: Loc.language.rawValue)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state(remaining: total, total: total, answered: 0),
                                         staleDate: nil))
        } catch {
            // Лимит активностей, выключено в настройках — сессия идёт и без неё.
            Log.warning(.app, "Live Activity не запустилась", detail: error.localizedDescription)
        }
    }

    func update(remaining: Int, total: Int, answered: Int) {
        guard let activity else { return }
        let content = ActivityContent(state: state(remaining: remaining, total: total, answered: answered),
                                      staleDate: nil)
        Task { await activity.update(content) }
    }

    /// Конец сессии: активность убирается сразу — итог и так на экране.
    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func state(remaining: Int, total: Int, answered: Int) -> SessionActivityAttributes.ContentState {
        let pace = SessionEstimate.secondsPerCard(answered: answered,
                                                  elapsed: Date().timeIntervalSince(startedAt))
        return .init(remaining: max(remaining, 0), total: total,
                     minutesLeft: SessionEstimate.minutesLeft(remaining: remaining, secondsPerCard: pace))
    }
}
