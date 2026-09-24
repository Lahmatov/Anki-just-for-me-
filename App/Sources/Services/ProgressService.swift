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
        let honest = honestReviews()
        let retells = (try? context.fetch(FetchDescriptor<RetellSession>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []

        let days = studyDays(of: honest)

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
    func streakStatus(freezesPerMonth: Int = 2, now: Date = Date()) -> StreakStatus {
        StreakCalculator.streakStatus(
            studyDays: studyDays(of: honestReviews()), now: now,
            cutoffHour: cutoffHour, freezesPerMonth: freezesPerMonth)
    }

    func weekProgress(target: Int = 5, now: Date = Date()) -> WeekProgress {
        StreakCalculator.weekProgress(
            studyDays: studyDays(of: honestReviews()), target: target, now: now,
            cutoffHour: cutoffHour)
    }

    /// Награды, серия и неделя считаются только по честным повторам — правки
    /// руками не в счёт. Одно место, чтобы три цифры не разошлись, если
    /// правило «честности» когда-нибудь поменяется.
    private func honestReviews() -> [Review] {
        ((try? context.fetch(FetchDescriptor<Review>())) ?? []).filter(\.isHonest)
    }

    private func studyDays(of reviews: [Review]) -> Set<Date> {
        StreakCalculator.studyDays(from: reviews.map(\.timestamp), cutoffHour: cutoffHour)
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
