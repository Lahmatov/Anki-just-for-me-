import Foundation

/// Обрыв запроса оттого, что приложение свернули, — а не настоящая ошибка.
///
/// Свёрнутое приложение iOS замораживает через несколько секунд, и запрос
/// падает с «соединение потеряно» или «отменено». Показывать это как
/// ошибку неправильно: человек ничего не сломал, и запрос надо просто
/// продолжить, когда он вернётся.
public enum NetworkInterruption {
    private static let codes: Set<URLError.Code> = [
        .networkConnectionLost, .cancelled, .timedOut, .notConnectedToInternet,
        .backgroundSessionWasDisconnected, .backgroundSessionInUseByAnotherProcess,
    ]

    /// Похоже ли это на обрыв, который стоит повторить.
    public static func isInterruption(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError { return codes.contains(urlError.code) }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && codes.contains(URLError.Code(rawValue: nsError.code))
    }

    /// Повторять ли запрос: только обрыв и только если приложение уходило
    /// в фон, пока запрос шёл. Обрыв на активном экране — это настоящая сеть,
    /// и молча крутить повтор там нельзя.
    public static func shouldResume(after error: Error, wasBackgrounded: Bool) -> Bool {
        wasBackgrounded && isInterruption(error)
    }
}
