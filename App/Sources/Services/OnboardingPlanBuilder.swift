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
            // Без стартового набора для языка шаг «с чего начать» не нужен.
            hasWords: !notes.isEmpty || !StarterDeck.isAvailable,
            needsBetterVoice: SpeechService.shared.shouldSuggestBetterVoice,
            hasGoal: ProgressService(context: context).activeContract != nil,
            hasReminder: defaults.bool(forKey: SettingsKey.reminderEnabled),
            hasChosenLanguage: defaults.string(forKey: SettingsKey.appLanguage) != nil,
            hasLevel: AppSettings.englishLevel != nil,
            hasStudyShow: defaults.string(forKey: SettingsKey.studyShow) != nil)
    }
}
