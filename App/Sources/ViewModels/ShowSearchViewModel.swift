import Foundation
import SwiftData
import Observation
import AJFMCore

/// Поиск сериала в TVMaze и добавление в «Мои сериалы».
@Observable
@MainActor
final class ShowSearchViewModel {
    var query = ""
    private(set) var results: [TVMaze.Show] = []
    private(set) var searching = false
    private(set) var adding: Int?
    private(set) var error: String?
    /// Уже добавленные — считаются вместе с результатами, а не запросом
    /// в базу на каждую строку при каждой перерисовке.
    private(set) var trackedIDs: Set<Int> = []

    func search(in context: ModelContext) async {
        searching = true
        error = nil
        defer { searching = false }
        let service = ShowService(context: context)
        do {
            results = try await service.search(query)
            trackedIDs = Set(results.map(\.id).filter { service.tracked(id: $0) != nil })
            if results.isEmpty {
                error = tr("Ничего не нашлось. Попробуй английское название.",
                           "Nada encontrado. Tenta o título em inglês.",
                           "Nothing found. Try the English title.")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// true — сериал добавлен, экран можно закрывать.
    func add(_ show: TVMaze.Show, in context: ModelContext) async -> Bool {
        adding = show.id
        defer { adding = nil }
        do {
            try await ShowService(context: context).add(show)
            trackedIDs.insert(show.id)
            Haptics.success()
            return true
        } catch {
            Haptics.failure()
            self.error = error.localizedDescription
            return false
        }
    }
}
