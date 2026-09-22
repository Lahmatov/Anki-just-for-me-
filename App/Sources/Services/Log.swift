import Foundation
import os
import AJFMCore

/// Единая точка записи событий.
///
/// Пишет сразу в два места: в системный журнал (видно в Console.app и Xcode,
/// когда телефон подключён к Mac) и в кольцевой буфер внутри приложения —
/// его видно прямо на экране «Журнал» в настройках. Второе важнее: без Mac
/// под рукой это единственный способ понять, что случилось, и переслать
/// подробности.
enum Log {
    private static let subsystem = "com.lahmatov.ajfm"

    private static func logger(for category: LogCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    static func debug(_ category: LogCategory, _ message: String, detail: String? = nil) {
        EventLog.shared.debug(category, message, detail: detail)
        logger(for: category).debug("\(message, privacy: .public)")
    }

    static func info(_ category: LogCategory, _ message: String, detail: String? = nil) {
        EventLog.shared.info(category, message, detail: detail)
        logger(for: category).info("\(message, privacy: .public)")
    }

    static func warning(_ category: LogCategory, _ message: String, detail: String? = nil) {
        EventLog.shared.warning(category, message, detail: detail)
        logger(for: category).warning("\(message, privacy: .public)")
    }

    static func error(_ category: LogCategory, _ message: String, detail: String? = nil) {
        EventLog.shared.error(category, message, detail: detail)
        logger(for: category).error("\(message, privacy: .public)")
    }

    /// Ошибка, пойманная в catch: сообщение отдельно, подробности отдельно.
    static func failure(_ category: LogCategory, _ message: String, _ error: Error) {
        Self.error(category, message, detail: error.localizedDescription)
    }
}
