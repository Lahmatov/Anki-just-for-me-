import Foundation

public enum LogLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case debug, info, warning, error

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ level: LogLevel) -> Int {
        switch level {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    public var title: String {
        switch self {
        case .debug: return tr("Отладка", "Depuração", "Debug")
        case .info: return tr("Событие", "Evento", "Event")
        case .warning: return tr("Внимание", "Atenção", "Warning")
        case .error: return tr("Ошибка", "Erro", "Error")
        }
    }

    public var symbol: String {
        switch self {
        case .debug: return "ant"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}

public enum LogCategory: String, Codable, Sendable, CaseIterable {
    case importing, review, speech, network, backup, rewards, app

    public var title: String {
        switch self {
        case .importing: return tr("Импорт", "Importação", "Import")
        case .review: return tr("Повторения", "Revisões", "Reviews")
        case .speech: return tr("Речь", "Fala", "Speech")
        case .network: return tr("Сеть", "Rede", "Network")
        case .backup: return tr("Бэкап", "Cópia de segurança", "Backup")
        case .rewards: return tr("Награды", "Recompensas", "Rewards")
        case .app: return tr("Приложение", "Aplicação", "App")
        }
    }
}

public struct LogEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var level: LogLevel
    public var category: LogCategory
    public var message: String
    /// Подробности, которые не нужны в строке списка, но нужны при разборе.
    public var detail: String?

    public init(
        id: UUID = UUID(), date: Date = Date(), level: LogLevel,
        category: LogCategory, message: String, detail: String? = nil
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
        self.detail = detail
    }
}

/// Кольцевой журнал событий в памяти.
///
/// Нужен потому, что консоль Xcode доступна только у Mac: чтобы понять, что
/// пошло не так на телефоне, журнал должен быть виден в самом приложении и
/// выгружаться одним нажатием.
///
/// Буфер ограничен: журнал не должен разрастаться и не должен ничего писать
/// на диск без спроса.
public final class EventLog: @unchecked Sendable {
    public static let shared = EventLog(limit: 500)

    private let lock = NSLock()
    private var entries: [LogEntry] = []
    private let limit: Int

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    public func append(_ entry: LogEntry) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    public func log(
        _ level: LogLevel, _ category: LogCategory, _ message: String,
        detail: String? = nil, date: Date = Date()
    ) {
        append(LogEntry(
            date: date, level: level, category: category,
            message: message, detail: detail))
    }

    public func debug(_ category: LogCategory, _ message: String, detail: String? = nil) {
        log(.debug, category, message, detail: detail)
    }

    public func info(_ category: LogCategory, _ message: String, detail: String? = nil) {
        log(.info, category, message, detail: detail)
    }

    public func warning(_ category: LogCategory, _ message: String, detail: String? = nil) {
        log(.warning, category, message, detail: detail)
    }

    public func error(_ category: LogCategory, _ message: String, detail: String? = nil) {
        log(.error, category, message, detail: detail)
    }

    /// Записи от новых к старым, с необязательными фильтрами.
    public func recent(
        minimumLevel: LogLevel = .debug, category: LogCategory? = nil, limit: Int? = nil
    ) -> [LogEntry] {
        lock.lock()
        let snapshot = entries
        lock.unlock()

        let filtered = snapshot
            .filter { $0.level >= minimumLevel }
            .filter { category == nil || $0.category == category }
            .reversed()
        guard let limit else { return Array(filtered) }
        return Array(filtered.prefix(limit))
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    /// Журнал в виде текста — его можно переслать одним нажатием.
    public func exportText(minimumLevel: LogLevel = .debug) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]

        let lines = recent(minimumLevel: minimumLevel).reversed().map { entry -> String in
            var line = "\(formatter.string(from: entry.date)) "
                + "[\(entry.level.rawValue)] [\(entry.category.rawValue)] \(entry.message)"
            if let detail = entry.detail, !detail.isEmpty {
                line += "\n    \(detail)"
            }
            return line
        }
        return lines.joined(separator: "\n")
    }
}
