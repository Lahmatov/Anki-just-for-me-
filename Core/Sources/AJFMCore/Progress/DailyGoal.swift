import Foundation

/// Дневная цель во времени: «15 минут в день» или «час в день».
///
/// Число карточек как цель обманчиво: двадцать новых слов и двадцать
/// лёгких повторов — очень разная работа. Время честнее и понятнее: его
/// легко вписать в день, как тренировку.
///
/// Время берётся из повторов — сколько секунд карточка была на экране.
/// Каждый повтор обрезается сверху: карточка, оставленная открытой на
/// полчаса, пока человек ушёл за чаем, не должна закрывать цель дня.
public enum DailyGoal {

    /// Варианты цели в минутах: от «хоть что-то» до двух часов.
    public static let options = [5, 10, 15, 20, 30, 45, 60, 90, 120]
    public static let defaultMinutes = 15
    /// Больше минуты на одну карточку — почти наверняка экран забыли открытым.
    public static let perReviewCap: TimeInterval = 60

    /// Учебные секунды по длительностям повторов, с обрезкой каждого.
    /// Отрицательное и нечисловое (сбитые часы, битая запись) — ноль.
    public static func studiedSeconds(_ durations: [TimeInterval]) -> TimeInterval {
        durations.reduce(0) { total, duration in
            guard duration.isFinite, duration > 0 else { return total }
            return total + min(duration, perReviewCap)
        }
    }

    /// Доля цели от 0 до 1. Без цели (ноль и меньше) доля нулевая:
    /// «выполнено» при отсутствии цели выглядело бы наградой ни за что.
    public static func progress(studiedSeconds: TimeInterval, goalMinutes: Int) -> Double {
        guard goalMinutes > 0, studiedSeconds.isFinite, studiedSeconds > 0 else { return 0 }
        return min(1, studiedSeconds / (Double(goalMinutes) * 60))
    }

    /// Полные минуты для показа: 59 секунд — ещё ноль минут, а не одна.
    public static func wholeMinutes(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(seconds / 60)
    }

    /// Цель словами: «15 минут», «1 час», «1 ч 30 мин».
    public static func format(minutes: Int) -> String {
        let minutes = max(0, minutes)
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return Counted.minutes(minutes) }
        let hoursText = trCount(hours, ru: ("час", "часа", "часов"),
                                pt: ("hora", "horas"), en: ("hour", "hours"))
        if rest == 0 { return hoursText }
        return tr("\(hours) ч \(rest) мин", "\(hours) h \(rest) min", "\(hours) h \(rest) min")
    }

    /// Сохранённое значение, приведённое к допустимому: мусор и ноль
    /// превращаются в цель по умолчанию, а не в «цель ноль минут».
    public static func sanitized(_ stored: Int) -> Int {
        stored > 0 && stored <= options.last! ? stored : defaultMinutes
    }
}
