import Foundation
import SwiftData
import AJFMCore

/// Набор, с которого начинается работа.
///
/// Пустой экран при первом запуске — худшее, чем можно встретить: учить нечего,
/// и непонятно, работает ли вообще что-нибудь. Поэтому в приложение вшит
/// стартовый набор: двадцать слов, без которых трудно рассказать, о чём была
/// серия. Он же служит проверкой, что импорт жив.
@MainActor
enum StarterDeck {
    static let resourceName = "starter-deck"

    static func data() -> Data? {
        guard let url = Bundle.main.url(
            forResource: resourceName, withExtension: "json") else {
            Log.warning(.app, "Стартовый набор не найден в ресурсах приложения")
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// Сколько слов в наборе — показывается на экране знакомства.
    static func wordCount() -> Int {
        guard let data = data(),
              let file = try? DeckParser.parse(data: data) else { return 0 }
        return file.notes.count
    }

    @discardableResult
    static func install(into context: ModelContext) -> ImportResult? {
        guard let data = data() else { return nil }
        do {
            let service = ImportService(context: context)
            let result = try service.apply(try service.makePlan(from: data))
            Log.info(
                .importing, "Стартовый набор добавлен",
                detail: "слов: \(result.addedNotes)")
            return result
        } catch {
            Log.failure(.importing, "Не удалось добавить стартовый набор", error)
            return nil
        }
    }
}
