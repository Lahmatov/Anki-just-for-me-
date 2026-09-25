import Foundation

/// Контракт на награду: «150 слов в долгосрочной памяти — и я покупаю себе диск».
///
/// Две вещи здесь принципиальны.
///
/// Первая: считаются **зрелые слова**, а не просмотры. Если засчитывать показы,
/// награду можно накликать за вечер, и она обесценится.
///
/// Вторая: прогресс считается от `baseline` — числа зрелых слов на момент
/// заключения контракта. Иначе новая цель оказалась бы выполнена в момент
/// создания, если выученного уже много.
public struct RewardContract: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// Сколько новых зрелых слов нужно набрать.
    public var goal: Int
    /// Что человек сам себе пообещал.
    public var reward: String
    public var startedAt: Date
    /// Сколько зрелых слов было на старте.
    public var baseline: Int
    public var deadline: Date?
    public var completedAt: Date?
    /// Прогресс правился руками — награда получена не совсем честно.
    public var hadManualAdjustments: Bool

    public init(
        id: UUID = UUID(),
        goal: Int,
        reward: String,
        startedAt: Date = Date(),
        baseline: Int,
        deadline: Date? = nil,
        completedAt: Date? = nil,
        hadManualAdjustments: Bool = false
    ) {
        self.id = id
        self.goal = max(1, goal)
        self.reward = reward
        self.startedAt = startedAt
        self.baseline = max(0, baseline)
        self.deadline = deadline
        self.completedAt = completedAt
        self.hadManualAdjustments = hadManualAdjustments
    }

    public var isCompleted: Bool { completedAt != nil }
}

public struct RewardProgress: Equatable, Sendable {
    public var done: Int
    public var goal: Int
    public var remaining: Int
    public var fraction: Double
    public var isReached: Bool
    /// Сколько дней осталось до срока, если он задан.
    public var daysLeft: Int?
    /// Сколько слов в день нужно, чтобы успеть.
    public var requiredPerDay: Double?
}

public enum RewardCalculator {

    public static func progress(
        contract: RewardContract, currentMatureWords: Int, now: Date = Date(),
        calendar: Calendar = .current
    ) -> RewardProgress {
        let done = max(0, currentMatureWords - contract.baseline)
        let remaining = max(0, contract.goal - done)
        let fraction = min(1, Double(done) / Double(contract.goal))

        var daysLeft: Int?
        var requiredPerDay: Double?
        if let deadline = contract.deadline {
            let days = calendar.dateComponents([.day], from: now, to: deadline).day ?? 0
            daysLeft = days
            if days > 0, remaining > 0 {
                requiredPerDay = Double(remaining) / Double(days)
            }
        }

        return RewardProgress(
            done: done,
            goal: contract.goal,
            remaining: remaining,
            fraction: fraction,
            isReached: done >= contract.goal,
            daysLeft: daysLeft,
            requiredPerDay: requiredPerDay)
    }

    /// Формулировка для экрана. Нарочно без восторгов: награду выдаёт факт,
    /// а не приложение.
    public static func statusLine(
        contract: RewardContract, progress: RewardProgress
    ) -> String {
        if contract.isCompleted {
            return contract.hadManualAdjustments
                ? tr("Выполнено, но прогресс правился руками.",
                     "Cumprido, mas o progresso foi corrigido à mão.",
                     "Done, but the progress was edited by hand.")
                : tr("Заслужено: \(contract.reward).",
                     "Merecido: \(contract.reward).",
                     "Earned: \(contract.reward).")
        }
        if progress.isReached {
            return tr("Цель достигнута. \(contract.reward) — иди забирай.",
                      "Objetivo cumprido. \(contract.reward) — vai buscar.",
                      "Goal reached. \(contract.reward) — go and claim it.")
        }
        if let days = progress.daysLeft, days <= 0 {
            return tr("Срок вышел: \(progress.done) из \(progress.goal).",
                      "O prazo acabou: \(progress.done) de \(progress.goal).",
                      "Time's up: \(progress.done) of \(progress.goal).")
        }
        return tr("До цели ещё ", "Faltam ", "") + Counted.words(progress.remaining)
            + tr(".", " para o objetivo.", " to go.")
    }
}
