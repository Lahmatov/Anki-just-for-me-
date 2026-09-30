import Foundation

/// Сколько примерно осталось до конца сессии — для Live Activity.
///
/// Среднее время на карточку берётся из уже отвеченных в этой сессии: к
/// середине сессии темп понятен. До первого ответа — обычные 8 секунд.
public enum SessionEstimate {
    public static let defaultSecondsPerCard: Double = 8

    public static func secondsPerCard(answered: Int, elapsed: TimeInterval) -> Double {
        guard answered > 0, elapsed > 0 else { return defaultSecondsPerCard }
        // Карточка дольше двух минут — человек отошёл, а не думал: в среднее
        // такой перерыв не должен раздувать прогноз.
        return min(elapsed / Double(answered), 120)
    }

    /// Минуты до конца, округлённые вверх; 0 — карточек не осталось.
    public static func minutesLeft(remaining: Int, secondsPerCard: Double) -> Int {
        guard remaining > 0 else { return 0 }
        let seconds = Double(remaining) * max(secondsPerCard, 1)
        return max(1, Int((seconds / 60).rounded(.up)))
    }
}
