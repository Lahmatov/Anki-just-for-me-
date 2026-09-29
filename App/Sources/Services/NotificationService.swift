import Foundation
import SwiftData
import UserNotifications
import AJFMCore

/// Локальные напоминания о повторении.
///
/// Это именно локальные уведомления, а не push: они работают и на бесплатном
/// аккаунте разработчика, без APNs и без сервера. См. docs/decisions.md, D-3.
enum NotificationService {
    static let dailyReminderID = "ajfm.daily-reminder"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Напоминания на ближайшие дни — по одному в день, разовые, а не
    /// повторяющееся: повторяющееся пришло бы и в день, когда уже занимались.
    static var reminderIDs: [String] {
        [dailyReminderID] + (0..<SmartReminder.daysAhead).map { "ajfm.reminder.\($0)" }
    }

    /// Во сколько напоминать: по привычке (умное время) или в выбранное.
    /// `learned` — время взято из истории, а не из настроек.
    @MainActor
    static func plannedTime(context: ModelContext, now: Date = Date())
        -> (time: SmartReminder.Time, learned: Bool) {
        let defaults = UserDefaults.standard
        let fixed = SmartReminder.Time(
            hour: defaults.object(forKey: SettingsKey.reminderHour) as? Int ?? 20,
            minute: defaults.object(forKey: SettingsKey.reminderMinute) as? Int ?? 0)
        guard defaults.object(forKey: SettingsKey.reminderSmart) as? Bool ?? true,
              let usual = SmartReminder.usualStart(
                sessions: ProgressService(context: context).honestReviewDates(), now: now,
                cutoffHour: AppSettings.load().dayCutoffHour) else {
            return (fixed, false)
        }
        return (SmartReminder.reminderTime(forUsual: usual), true)
    }

    /// Перестроить напоминания: при запуске, уходе в фон и после сессии.
    /// Отозванное разрешение не спрашиваем заново — просто ничего не ставим.
    @MainActor
    static func reschedule(context: ModelContext, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: reminderIDs)
        guard UserDefaults.standard.bool(forKey: SettingsKey.reminderEnabled) else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let planned = plannedTime(context: context, now: now)
        let studied = ProgressService(context: context).studiedSecondsToday(now: now) > 0
        let dates = SmartReminder.schedule(
            at: planned.time, now: now, studiedToday: studied,
            cutoffHour: AppSettings.load().dayCutoffHour)
        for (index, date) in dates.enumerated() {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date)
            let request = UNNotificationRequest(
                identifier: "ajfm.reminder.\(index)", content: reminderContent(daysAway: index),
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
        }
        Log.info(.app, "Напоминания перестроены",
                 detail: "\(dates.count), " + String(format: "%02d:%02d", planned.time.hour, planned.time.minute)
                    + (planned.learned ? " по привычке" : ""))
    }

    /// Разные слова в разные дни: одно и то же сообщение неделю подряд
    /// перестают читать уже на третий день.
    static func reminderContent(daysAway: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let texts: [(String, String)] = [
            (tr("Время повторить", "Hora de rever", "Time to review"),
             tr("Карточки ждут. Пятнадцать минут — и день закрыт.",
                "Os cartões estão à espera. Quinze minutos e o dia fica feito.",
                "Your cards are waiting. Fifteen minutes and the day is done.")),
            (tr("Мончик ждёт", "O Monchik está à espera", "Monchik is waiting"),
             tr("Обычно в это время ты уже занимаешься. Пара карточек?",
                "Por esta hora costumas estar a estudar. Uns cartões?",
                "You're usually studying by now. A few cards?")),
            (tr("Серия не должна прерваться", "A série não pode parar", "Keep the streak alive"),
             tr("Одна короткая сессия — и огонёк горит дальше.",
                "Uma sessão curta e a chama continua acesa.",
                "One short session keeps the flame going.")),
        ]
        let text = texts[daysAway % texts.count]
        content.title = text.0
        content.body = text.1
        content.sound = .default
        content.threadIdentifier = "daily-reminder"
        return content
    }

    static func cancelDailyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: reminderIDs)
    }

    /// Ответ Monchik Help пришёл, пока приложение свёрнуто.
    static func notifyHelpReply(_ text: String) async {
        let content = UNMutableNotificationContent()
        content.title = tr("Мончик ответил", "O Monchik respondeu", "Monchik replied")
        content.body = String(text.prefix(180))
        content.sound = .default
        content.threadIdentifier = "monchik-help"
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "monchik-help-\(UUID().uuidString)",
                                  content: content, trigger: nil))
    }

    /// Разрешение спрашиваем, только если его ещё не спрашивали: второй раз
    /// iOS окно не покажет, а отказ человека надо уважать.
    static func requestIfUndetermined() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = await requestAuthorization()
        }
    }
}
