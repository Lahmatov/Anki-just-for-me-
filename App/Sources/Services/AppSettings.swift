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
    static let deckModel = "deckModel"
    static let monthlyBudget = "monthlyBudget"
    static let bestPronunciationStreak = "bestPronunciationStreak"
    static let perfectSessions = "perfectSessions"
    static let weeklyTarget = "weeklyTarget"
    static let lastBackupDate = "lastBackupDate"
    static let lastCloudBackupDate = "lastCloudBackupDate"
    static let deviceID = "deviceID"
    static let leechThreshold = "leechThreshold"
    /// Устаревший флаг «знакомство пройдено» — читается только для перехода
    /// на версии (`OnboardingPlan.seenVersion`).
    static let onboardingDone = "onboardingDone"
    /// Согласие на отправку текста в Anthropic (`AIConsent`).
    static let aiConsent = "aiConsent"
    /// Дневная цель в минутах (`DailyGoal`).
    static let dailyMinutesGoal = "dailyMinutesGoal"
    /// Какую версию знакомства человек уже видел.
    static let onboardingVersion = "onboardingVersion"
    static let lastLaunchAnimation = "lastLaunchAnimation"
    static let reminderEnabled = "reminderEnabled"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"
    static let appLanguage = "appLanguage"
    static let englishLevel = "englishLevel"
    static let fontStyle = "fontStyle"
    /// Имя и выбор аватарки в профиле (`ProfileStore`). Только на телефоне.
    static let profileName = "profileName"
    static let profileAvatar = "profileAvatar"
    /// День, когда уже праздновали цель дня, и серия, до которой праздновали
    /// отметки (`Celebration`): праздник — один раз, а не на каждом открытии.
    static let goalCelebratedDay = "goalCelebratedDay"
    static let celebratedStreak = "celebratedStreak"
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

    /// Сменить язык: сначала для строк, потом в хранилище — запись в
    /// хранилище перестраивает экраны, и к этому моменту строки уже
    /// должны отдаваться на новом языке.
    static func setLanguage(_ language: AppLanguage) {
        Loc.language = language
        UserDefaults.standard.set(language.rawValue, forKey: SettingsKey.appLanguage)
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
