import Foundation
import SwiftUI
import AJFMCore

/// Настройки приложения. Живут в UserDefaults — их немного и они несложные.
enum SettingsKey {
    static let newPerDay = "newPerDay"
    static let reviewsPerDay = "reviewsPerDay"
    static let burySiblings = "burySiblings"
    static let dayCutoffHour = "dayCutoffHour"
    static let desiredRetention = "desiredRetention"
    static let autoSpeak = "autoSpeak"
    static let claudeModel = "claudeModel"
    static let monthlyBudget = "monthlyBudget"
    static let bestPronunciationStreak = "bestPronunciationStreak"
    static let perfectSessions = "perfectSessions"
    static let weeklyTarget = "weeklyTarget"
    static let lastBackupDate = "lastBackupDate"
    static let leechThreshold = "leechThreshold"
    static let onboardingDone = "onboardingDone"
    static let lastLaunchAnimation = "lastLaunchAnimation"
    static let reminderEnabled = "reminderEnabled"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"
    static let appLanguage = "appLanguage"
    static let englishLevel = "englishLevel"
    static let fontStyle = "fontStyle"
}

extension AppSettings {
    /// Язык интерфейса и переводов. Пока человек не выбрал сам — берётся
    /// из системы, так что первый запуск сразу на понятном языке.
    static var language: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: SettingsKey.appLanguage),
           let chosen = AppLanguage(rawValue: raw) {
            return chosen
        }
        return AppLanguage.resolve(preferred: Locale.preferredLanguages)
    }

    /// Уровень по тесту, если тест пройден.
    static var englishLevel: CEFRLevel? {
        UserDefaults.standard.string(forKey: SettingsKey.englishLevel)
            .flatMap(CEFRLevel.init(rawValue:))
    }
}

struct AppSettings {
    var newPerDay: Int
    var reviewsPerDay: Int
    var burySiblings: Bool
    var dayCutoffHour: Int
    var desiredRetention: Double

    static let `default` = AppSettings(
        newPerDay: 20, reviewsPerDay: 200, burySiblings: true,
        dayCutoffHour: 4, desiredRetention: 0.9)

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        AppSettings(
            newPerDay: value(defaults, SettingsKey.newPerDay, `default`.newPerDay),
            reviewsPerDay: value(defaults, SettingsKey.reviewsPerDay, `default`.reviewsPerDay),
            burySiblings: defaults.object(forKey: SettingsKey.burySiblings) as? Bool
                ?? `default`.burySiblings,
            dayCutoffHour: value(defaults, SettingsKey.dayCutoffHour, `default`.dayCutoffHour),
            desiredRetention: defaults.object(forKey: SettingsKey.desiredRetention) as? Double
                ?? `default`.desiredRetention)
    }

    private static func value(_ defaults: UserDefaults, _ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }

    var queueConfig: QueueConfig {
        QueueConfig(
            newPerDay: newPerDay,
            reviewsPerDay: reviewsPerDay,
            burySiblings: burySiblings,
            dayCutoffHour: dayCutoffHour)
    }
}
