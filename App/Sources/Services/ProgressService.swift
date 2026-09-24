import Foundation
import SwiftData
import AJFMCore

/// Сбор статистики, по которой считаются награды и ачивки.
@MainActor
struct ProgressService {
    let context: ModelContext
    var cutoffHour: Int = AppSettings.load().dayCutoffHour

    /// Число слов, дошедших до долгосрочной памяти.
    ///
    /// Считаются именно слова, а не карточки: пять карточек одного слова —
    /// это всё равно одно выученное слово, и награду они удваивать не должны.
    func matureWordCount() -> Int {
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let matureNotes = cards
            .filter(\.isMature)
            .compactMap { $0.note?.persistentModelID }
        return Set(matureNotes).count
    }

    func stats() -> LearningStats {
        let reviews = (try? context.fetch(FetchDescriptor<Review>())) ?? []
        // Награды считаются только по честным повторам — правки руками не в счёт.
        let honest = reviews.filter(\.isHonest)
        let retells = (try? context.fetch(FetchDescriptor<RetellSession>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []

        let days = StreakCalculator.studyDays(
            from: honest.map(\.timestamp), cutoffHour: cutoffHour)

        return LearningStats(
            matureWords: matureWordCount(),
            totalWords: notes.count,
            honestReviews: honest.count,
            // Серия с заморозками: та же цифра, что на главном экране, иначе
            // достижение «неделя подряд» спорило бы с тем, что видно глазами.
            currentStreakDays: StreakCalculator.streakStatus(
                studyDays: days, cutoffHour: cutoffHour).days,
            retellCount: retells.count,
            bestRetellCoverage: retells.map(\.coverage).max() ?? 0,
            pronunciationStreak: UserDefaults.standard
                .integer(forKey: SettingsKey.bestPronunciationStreak),
            perfectSessions: UserDefaults.standard
                .integer(forKey: SettingsKey.perfectSessions))
    }

    /// Серия учебных дней с автоматическими заморозками.
    func streakStatus(freezesPerMonth: Int = 2) -> StreakStatus {
        let reviews = (try? context.fetch(FetchDescriptor<Review>())) ?? []
        let days = StreakCalculator.studyDays(
            from: reviews.filter(\.isHonest).map(\.timestamp), cutoffHour: cutoffHour)
        return StreakCalculator.streakStatus(
            studyDays: days, cutoffHour: cutoffHour, freezesPerMonth: freezesPerMonth)
    }

    func weekProgress(target: Int = 5) -> WeekProgress {
        let reviews = (try? context.fetch(FetchDescriptor<Review>())) ?? []
        let days = StreakCalculator.studyDays(
            from: reviews.filter(\.isHonest).map(\.timestamp), cutoffHour: cutoffHour)
        return StreakCalculator.weekProgress(
            studyDays: days, target: target, cutoffHour: cutoffHour)
    }

    // MARK: - Контракты

    func contracts() -> [RewardContract] {
        ((try? context.fetch(FetchDescriptor<RewardContractEntity>())) ?? [])
            .map(\.asContract)
            .sorted { $0.startedAt > $1.startedAt }
    }

    var activeContract: RewardContract? {
        contracts().first { !$0.isCompleted }
    }

    /// Заводит контракт от текущего числа выученных слов.
    func createContract(goal: Int, reward: String, deadline: Date? = nil) {
        let contract = RewardContract(
            goal: goal, reward: reward, baseline: matureWordCount(), deadline: deadline)
        context.insert(RewardContractEntity(contract: contract))
        try? context.save()
        Log.info(
            .rewards, "Цель заведена: \(reward)",
            detail: "нужно \(goal) слов, сейчас выучено \(contract.baseline)")
    }

    /// Отмечает награду полученной.
    func complete(_ contract: RewardContract) {
        guard let entity = entity(for: contract.id) else { return }
        entity.completedAt = Date()
        try? context.save()
        Log.info(
            .rewards, "Награда получена: \(contract.reward)",
            detail: contract.hadManualAdjustments
                ? "прогресс правился руками"
                : "честно, \(contract.goal) слов")
    }

    func delete(_ contract: RewardContract) {
        guard let entity = entity(for: contract.id) else { return }
        context.delete(entity)
        try? context.save()
    }

    /// Помечает контракт как тронутый руками — чтобы награда не выглядела
    /// честно заработанной, если прогресс правили вручную.
    func markManualAdjustment() {
        guard let active = activeContract, let entity = entity(for: active.id) else { return }
        entity.hadManualAdjustments = true
        try? context.save()
    }

    private func entity(for id: UUID) -> RewardContractEntity? {
        ((try? context.fetch(FetchDescriptor<RewardContractEntity>())) ?? [])
            .first { $0.id == id }
    }

    // MARK: - Счётчики вне базы

    static func recordSessionResult(accurate: Bool) {
        guard accurate else { return }
        let defaults = UserDefaults.standard
        defaults.set(
            defaults.integer(forKey: SettingsKey.perfectSessions) + 1,
            forKey: SettingsKey.perfectSessions)
    }

    static func recordPronunciationStreak(_ streak: Int) {
        let defaults = UserDefaults.standard
        if streak > defaults.integer(forKey: SettingsKey.bestPronunciationStreak) {
            defaults.set(streak, forKey: SettingsKey.bestPronunciationStreak)
        }
    }
}
