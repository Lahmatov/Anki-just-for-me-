import ActivityKit
import Foundation

/// Live Activity сессии повторения: сколько карточек осталось. Общий файл
/// для приложения (запускает и обновляет) и виджета (рисует на экране
/// блокировки и в Dynamic Island).
struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var remaining: Int
        var total: Int
        var minutesLeft: Int
    }

    var deckName: String
    /// Язык интерфейса: виджет в своём процессе настроек приложения не видит.
    var language: String
}
