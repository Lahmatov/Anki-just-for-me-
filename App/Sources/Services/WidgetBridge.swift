import Foundation
import SwiftData
import WidgetKit
import AJFMCore

/// Передача цифр виджету: снимок в общей группе приложений.
///
/// Группа (App Groups) есть только у платного аккаунта разработчика —
/// как и вход через Apple, она включается в Config/Signing.xcconfig.
/// Без неё виджет ставится, но показывает приглашение открыть приложение.
@MainActor
enum WidgetBridge {
    /// Имя группы из Info.plist; пустое или неподставленное — группы нет.
    static var groupID: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RecapAppGroup") as? String,
              !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
        return raw
    }

    static func update(context: ModelContext, now: Date = Date()) {
        guard let groupID, let defaults = UserDefaults(suiteName: groupID) else { return }
        let snapshot = makeSnapshot(context: context, now: now)
        do {
            defaults.set(try snapshot.encoded(), forKey: WidgetSnapshot.defaultsKey)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            Log.failure(.app, "Снимок для виджета не записался", error)
        }
    }

    static func makeSnapshot(context: ModelContext, now: Date = Date()) -> WidgetSnapshot {
        let settings = AppSettings.load()
        let progress = ProgressService(context: context, cutoffHour: settings.dayCutoffHour)
        let due = (try? ReviewService(context: context).todayQueue(now: now))?.summary.total ?? 0
        let seconds = progress.studiedSecondsToday(now: now)
        let goalMinutes = UserDefaults.standard.object(forKey: SettingsKey.dailyMinutesGoal) as? Int
            ?? DailyGoal.defaultMinutes
        return WidgetSnapshot(
            dueCards: due,
            streakDays: progress.streakStatus(now: now).days,
            studiedToday: seconds > 0,
            goalFraction: DailyGoal.progress(studiedSeconds: seconds, goalMinutes: goalMinutes),
            studyDay: ReviewQueueBuilder.studyDayStart(for: now, cutoffHour: settings.dayCutoffHour),
            cutoffHour: settings.dayCutoffHour,
            language: Loc.language.rawValue)
    }
}
