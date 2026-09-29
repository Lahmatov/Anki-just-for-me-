import Foundation
import AJFMCore

/// Клиент сервера Recap (backend/).
///
/// Что здесь сознательно НЕ хранится: ключа Anthropic, промптов и лимитов.
/// Приложение знает только адрес сервера и токен своего устройства
/// (в Keychain, только на этом телефоне). Всё, что стоит денег, решает
/// сервер — взломанная копия приложения не получит больше, чем честная.
@MainActor
final class RecapBackend {
    static let shared = RecapBackend()

    private let session: URLSession
    private var registration: Task<String, Error>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Адрес из Info.plist; заглушка «CHANGE-ME» значит «сервер не подключён».
    static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RecapBackendURL") as? String,
              !raw.contains("CHANGE-ME"),
              let url = URL(string: raw), url.scheme == "https" else { return nil }
        return url
    }

    static var isConfigured: Bool { baseURL != nil }

    // MARK: - Методы API

    func plan() async throws -> BackendAPI.PlanStatus {
        try await send("GET", "/v1/me")
    }

    func redeem(code: String) async throws -> BackendAPI.PlanStatus {
        try await send("POST", "/v1/promo/redeem", body: encode(["code": code]))
    }

    func verifySubscription(transactionID: UInt64) async throws -> BackendAPI.PlanStatus {
        try await send("POST", "/v1/subscription/verify",
                       body: encode(["transactionId": String(transactionID)]))
    }

    func deck(_ body: BackendAPI.DeckBody) async throws -> BackendAPI.DeckResponse {
        try await send("POST", "/v1/deck", body: encode(body), timeout: 90)
    }

    func discuss(_ body: BackendAPI.DiscussBody) async throws -> BackendAPI.DiscussResponse {
        try await send("POST", "/v1/discuss", body: encode(body), timeout: 60)
    }

    /// Стереть это устройство на сервере — часть «Удалить все данные».
    /// Не зарегистрировано — стирать нечего, лишнюю регистрацию не делаем.
    func forgetDevice() async throws {
        guard Keychain.get(Keychain.recapDeviceToken) != nil else { return }
        struct Deleted: Decodable { let deleted: Bool }
        do {
            let _: Deleted = try await send("DELETE", "/v1/me", retrying: false)
        } catch let failure as BackendAPI.Failure where failure.code == "unauthorized" {
            // Сервер это устройство уже не знает — значит, и стирать нечего.
        }
        Keychain.remove(Keychain.recapDeviceToken)
    }

    func catalog() async throws -> [BackendAPI.CatalogShow] {
        let response: BackendAPI.CatalogResponse = try await send("GET", "/v1/catalog")
        return response.shows
    }

    // MARK: - Транспорт

    private func encode(_ value: some Encodable) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func send<Response: Decodable>(
        _ method: String, _ path: String, body: Data? = nil,
        timeout: TimeInterval = 20, retrying: Bool = true
    ) async throws -> Response {
        guard let base = Self.baseURL else { throw BackendAPI.Failure.notConfigured }
        let token = try await deviceToken()

        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = body
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendAPI.Failure.network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        // Сервер не знает токен (база сервера сброшена) — новое устройство
        // и ещё одна попытка. Доступ по промокоду при этом не вернуть,
        // а подписку приложение восстановит само при следующей проверке.
        if status == 401, retrying {
            Keychain.remove(Keychain.recapDeviceToken)
            return try await send(method, path, body: body, timeout: timeout, retrying: false)
        }
        guard (200..<300).contains(status) else {
            let failure = BackendAPI.Failure.from(status: status, body: data)
            Log.warning(.network, "Сервер Recap: \(failure.code ?? "?")", detail: "\(method) \(path)")
            throw failure
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw BackendAPI.Failure.server(code: "bad_response", status: status)
        }
    }

    /// Токен устройства: из Keychain, а при первом обращении — регистрация.
    /// Параллельные запросы ждут одну регистрацию, а не плодят устройства.
    private func deviceToken() async throws -> String {
        if let token = Keychain.get(Keychain.recapDeviceToken), !token.isEmpty { return token }
        if let registration { return try await registration.value }
        let task = Task { () throws -> String in
            guard let base = Self.baseURL else { throw BackendAPI.Failure.notConfigured }
            var request = URLRequest(url: base.appending(path: "/v1/devices"))
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 201,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = object["token"] as? String, !token.isEmpty else {
                throw BackendAPI.Failure.from(status: status, body: data)
            }
            Keychain.set(token, for: Keychain.recapDeviceToken)
            Log.info(.network, "Устройство зарегистрировано на сервере Recap")
            return token
        }
        registration = task
        defer { registration = nil }
        do {
            return try await task.value
        } catch let failure as BackendAPI.Failure {
            throw failure
        } catch {
            throw BackendAPI.Failure.network
        }
    }
}
