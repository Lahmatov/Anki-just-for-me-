import Foundation
import AJFMCore

/// SQL по HTTPS к Neon — тем же протоколом, что официальный драйвер.
/// Кодирование и разбор — в ядре (`NeonSQL`), здесь только сеть.
struct NeonClient {
    let connection: NeonConnection

    /// Запросы выполняются одной транзакцией: либо все, либо ни одного.
    func run(_ queries: [NeonQuery]) async throws -> [NeonResult] {
        var request = URLRequest(url: connection.endpoint)
        request.httpMethod = "POST"
        for (field, value) in NeonSQL.headers(for: connection) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try NeonSQL.body(queries)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NeonError.server(
                status: http.statusCode, message: NeonSQL.errorMessage(from: data))
        }
        return try NeonSQL.parse(data, batch: queries.count > 1)
    }

    func run(_ query: NeonQuery) async throws -> NeonResult {
        guard let result = try await run([query]).first else { throw NeonError.badResponse }
        return result
    }
}
