import Foundation
import SwiftData
import AJFMCore

/// Собирает план знакомства по фактическому состоянию приложения.
@MainActor
enum OnboardingPlanBuilder {
    static func make(context: ModelContext) -> OnboardingPlan {
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        let defaults = UserDefaults.standard

        return OnboardingPlan.make(
            hasWords: !notes.isEmpty,
            needsBetterVoice: SpeechService.shared.shouldSuggestBetterVoice,
            hasGoal: ProgressService(context: context).activeContract != nil,
            hasReminder: defaults.bool(forKey: SettingsKey.reminderEnabled),
            hasChosenLanguage: defaults.string(forKey: SettingsKey.appLanguage) != nil,
            hasLevel: AppSettings.englishLevel != nil)
    }
}
