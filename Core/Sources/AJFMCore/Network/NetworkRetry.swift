import Foundation

/// Что случилось с сетью — по коду `URLError` (P-80). Отдельно от
/// Foundation-типа: правило проверяется тестом, а коды стабильны годами.
public enum NetworkProblem: Equatable, Sendable {
    /// Сети нет совсем (авиарежим, нет покрытия, сотовые данные запрещены).
    case offline
    /// Сеть есть, но ответ не пришёл вовремя — медленный интернет.
    case slow
    /// Связь оборвалась посреди запроса: смена Wi-Fi на сотовую, лифт, метро.
    case dropped
    case other

    /// Коды `URLError.Code` (их rawValue).
    public init(urlErrorCode code: Int) {
        switch code {
        case -1009, -1020, -1018: self = .offline        // notConnectedToInternet, dataNotAllowed, internationalRoamingOff
        case -1001: self = .slow                          // timedOut
        case -1005, -1004, -1003, -1006: self = .dropped  // connectionLost, cannotConnectToHost, cannotFindHost, dnsLookupFailed
        default: self = .other
        }
    }
}

public enum NetworkRetryPolicy {
    /// Повторов не больше одного: дольше человек ждать не станет, а сервер
    /// под нагрузкой не надо добивать.
    public static let maxRetries = 1

    /// Через сколько повторить или nil — не повторять.
    ///
    /// Повторяются только запросы, которые безопасно отправить дважды:
    /// чтение и удаление, а также наборы слов — у них номер запроса, и
    /// сервер второй раз отдаёт готовый ответ, а не списывает лимит заново.
    /// Без сети повтор бесполезен — сразу честное «нет связи».
    public static func delay(for problem: NetworkProblem, attempt: Int, idempotent: Bool) -> Duration? {
        guard idempotent, attempt < maxRetries else { return nil }
        switch problem {
        case .dropped: return .milliseconds(600)
        case .slow: return .seconds(1)
        case .offline, .other: return nil
        }
    }
}
