import Foundation

/// Ошибки облачной базы.
public enum NeonError: Error, Equatable, LocalizedError {
    case invalidConnectionString
    case server(status: Int, message: String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .invalidConnectionString:
            return tr("Строка подключения не похожа на адрес Neon. Скопируй её целиком "
                        + "в консоли Neon: Connect → Connection string.",
                      "A ligação não parece um endereço do Neon. Copia-a inteira na "
                        + "consola do Neon: Connect → Connection string.",
                      "That doesn't look like a Neon connection string. Copy the whole "
                        + "thing from the Neon console: Connect → Connection string.")
        case .server(let status, let message):
            return tr("Neon ответил \(status): \(message)",
                      "O Neon respondeu \(status): \(message)",
                      "Neon replied \(status): \(message)")
        case .badResponse:
            return tr("Neon вернул ответ в непонятном формате.",
                      "O Neon devolveu uma resposta num formato inesperado.",
                      "Neon returned a reply in an unexpected format.")
        }
    }
}

/// Подключение к Neon по строке вида
/// `postgresql://user:password@ep-name-123.region.aws.neon.tech/db?sslmode=require`.
///
/// Драйвера Postgres для Swift на iOS нет, а открытый сокет к базе с телефона —
/// лишняя поверхность атаки. Neon принимает SQL по HTTPS — тем же путём ходит
/// его официальный драйвер `@neondatabase/serverless`: POST на `api.<регион>/sql`,
/// строка подключения в заголовке, запрос и параметры — в теле.
public struct NeonConnection: Equatable, Sendable {
    public let connectionString: String
    public let host: String
    public let user: String
    public let database: String

    public init(connectionString raw: String) throws {
        let trimmed = Self.extract(from: raw)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "postgres" || scheme == "postgresql",
              let host = components.host, host.split(separator: ".").count >= 3,
              let user = components.user, !user.isEmpty,
              let password = components.password, !password.isEmpty else {
            throw NeonError.invalidConnectionString
        }
        let database = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.connectionString = trimmed
        self.host = host
        self.user = user
        self.database = database.isEmpty ? "neondb" : database
    }

    /// Консоль Neon предлагает и голую строку, и команду `psql '…'` —
    /// из команды берём саму строку, кавычки отбрасываем.
    static func extract(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = text.range(of: "postgres", options: .caseInsensitive) {
            text = String(text[start.lowerBound...])
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "'\" \n\t"))
    }

    /// Адрес SQL-по-HTTP: первое звено хоста заменяется на `api`, как делает
    /// официальный драйвер. Пулер (`ep-…-pooler`) и прямой хост дают один адрес.
    public var endpoint: URL {
        let rest = host.split(separator: ".", maxSplits: 1).last.map(String.init) ?? host
        return URL(string: "https://api.\(rest)/sql")!
    }

    /// Для экрана и журнала: без пароля.
    public var redacted: String { "\(user)@\(host)/\(database)" }
}

/// Значение параметра запроса. Neon, как и `node-postgres`, принимает
/// параметры строками — приведение типов делает сам Postgres по `$1::тип`.
public enum NeonValue: Equatable, Sendable {
    case text(String)
    case null

    public static func int(_ value: Int) -> NeonValue { .text(String(value)) }

    var json: Any {
        switch self {
        case .text(let value): return value
        case .null: return NSNull()
        }
    }
}

/// Один запрос с параметрами `$1, $2…`. Значения никогда не вклеиваются
/// в текст запроса — только параметрами.
public struct NeonQuery: Equatable, Sendable {
    public var sql: String
    public var params: [NeonValue]

    public init(_ sql: String, _ params: [NeonValue] = []) {
        self.sql = sql
        self.params = params
    }

    var json: [String: Any] {
        ["query": sql, "params": params.map(\.json)]
    }
}

/// Результат одного запроса. Значения — текстом, как их отдаёт Postgres
/// (режим `Neon-Raw-Text-Output`): разбор типов — на стороне вызывающего.
public struct NeonResult: Equatable, Sendable {
    public var fields: [String]
    public var rows: [[String?]]

    public init(fields: [String], rows: [[String?]]) {
        self.fields = fields
        self.rows = rows
    }

    /// Значение колонки по имени в строке `row`.
    public func value(_ column: String, row: Int) -> String? {
        guard let index = fields.firstIndex(of: column), row < rows.count,
              index < rows[row].count else { return nil }
        return rows[row][index]
    }
}

/// Кодирование запросов и разбор ответов SQL-по-HTTP. Без сети — чтобы
/// проверять тестами.
public enum NeonSQL {

    public static func headers(for connection: NeonConnection) -> [String: String] {
        [
            "Neon-Connection-String": connection.connectionString,
            "Neon-Raw-Text-Output": "true",
            "Neon-Array-Mode": "true",
            "Content-Type": "application/json",
        ]
    }

    /// Несколько запросов одним вызовом выполняются в одной транзакции:
    /// либо все, либо ни одного.
    public static func body(_ queries: [NeonQuery]) throws -> Data {
        let object: [String: Any] = queries.count == 1
            ? queries[0].json
            : ["queries": queries.map(\.json)]
        return try JSONSerialization.data(withJSONObject: object)
    }

    public static func parse(_ data: Data, batch: Bool) throws -> [NeonResult] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NeonError.badResponse
        }
        if batch {
            guard let results = object["results"] as? [[String: Any]] else {
                throw NeonError.badResponse
            }
            return try results.map(parseOne)
        }
        return [try parseOne(object)]
    }

    static func parseOne(_ object: [String: Any]) throws -> NeonResult {
        guard let fields = object["fields"] as? [[String: Any]] else {
            throw NeonError.badResponse
        }
        let rows = (object["rows"] as? [[Any]] ?? []).map { row in
            row.map { value -> String? in
                if value is NSNull { return nil }
                if let text = value as? String { return text }
                return "\(value)"
            }
        }
        return NeonResult(fields: fields.map { $0["name"] as? String ?? "" }, rows: rows)
    }

    /// Текст ошибки: на 400 Neon отдаёт JSON с `message`, иначе — просто текст.
    public static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
    }
}
