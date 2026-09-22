import Foundation
import UserNotifications

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

    static func scheduleDailyReminder(hour: Int, minute: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderID])

        let content = UNMutableNotificationContent()
        content.title = "Время повторить"
        content.body = "Карточки ждут. Пятнадцать минут — и день закрыт."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let request = UNNotificationRequest(
            identifier: dailyReminderID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
        try? await center.add(request)
    }

    static func cancelDailyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [dailyReminderID])
    }
}
