import Foundation
import AJFMCore

/// Поиск фильмов в каталоге Apple. Разбор — в ядре (`AppleMovies`), здесь только сеть.
struct MovieSearchClient {
    var session: URLSession = .shared

    enum Failure: LocalizedError {
        case unavailable

        var errorDescription: String? {
            tr("Каталог фильмов не ответил. Проверь интернет и попробуй ещё раз.",
               "O catálogo de filmes não respondeu. Verifica a internet e tenta de novo.",
               "The movie catalog didn't answer. Check the connection and try again.")
        }
    }

    func search(_ term: String) async throws -> [Movie] {
        guard let url = AppleMovies.searchURL(term) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.unavailable }
            return try AppleMovies.parseSearch(data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.warning(.network, "Поиск фильма не удался", detail: term)
            throw Failure.unavailable
        }
    }
}
