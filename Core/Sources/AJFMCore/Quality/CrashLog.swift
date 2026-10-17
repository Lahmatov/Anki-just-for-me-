import Foundation

/// Сбои и зависания, о которых iOS сообщила через MetricKit (P-74).
///
/// Своё вместо стороннего сервиса сбоев: отчёты MetricKit приходят на сам
/// телефон и никуда не уходят. В обращение в поддержку попадает только
/// сводка — сколько было и какого рода, — и только если человек не выключил
/// диагностику. Так мы знаем о падениях, не отдавая данные ещё одной компании.
public struct CrashRecord: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case crash, hang }

    public var kind: Kind
    public var date: Date
    /// «SIGSEGV», «EXC_BAD_ACCESS» — тип, без адресов и стека.
    public var reason: String
    public var appVersion: String

    public init(kind: Kind, date: Date, reason: String, appVersion: String) {
        self.kind = kind
        self.date = date
        self.reason = String(reason.prefix(40))
        self.appVersion = String(appVersion.prefix(20))
    }
}

public enum CrashLog {
    public static let keepDays = 30
    public static let limit = 50

    /// Добавить записи, убрать старше месяца и лишние — новые остаются.
    public static func merge(_ existing: [CrashRecord], adding new: [CrashRecord], now: Date) -> [CrashRecord] {
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        return (existing + new)
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .suffix(limit)
            .map { $0 }
    }

    /// Причина сбоя по-человечески: имя сигнала или исключения Mach.
    public static func reason(signal: Int?, exceptionType: Int?) -> String {
        let signals = [4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 8: "SIGFPE", 9: "SIGKILL",
                       10: "SIGBUS", 11: "SIGSEGV", 13: "SIGPIPE"]
        let exceptions = [1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC",
                          6: "EXC_BREAKPOINT", 10: "EXC_CRASH", 11: "EXC_RESOURCE", 12: "EXC_GUARD"]
        if let exceptionType, let name = exceptions[exceptionType] { return name }
        if let signal, let name = signals[signal] { return name }
        if let signal { return "signal \(signal)" }
        return "unknown"
    }

    /// Сводка для диагностики обращения: «crashes 2 · hangs 1 · last SIGSEGV 0.4 (17)».
    public static func summary(_ records: [CrashRecord]) -> [String: String] {
        guard !records.isEmpty else { return [:] }
        var result = [
            "crashes": String(records.filter { $0.kind == .crash }.count),
            "hangs": String(records.filter { $0.kind == .hang }.count),
        ]
        if let last = records.last(where: { $0.kind == .crash }) {
            result["lastCrash"] = "\(last.reason) \(last.appVersion)"
        }
        return result
    }
}
