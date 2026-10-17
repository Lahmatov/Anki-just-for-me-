import Foundation
import SwiftData
import AJFMCore

/// Набор, с которого начинается работа.
///
/// Пустой экран при первом запуске — худшее, чем можно встретить: учить нечего,
/// и непонятно, работает ли вообще что-нибудь. Поэтому в приложение вшит
/// стартовый набор: двадцать слов, без которых трудно рассказать, о чём была
/// серия. Он же служит проверкой, что импорт жив.
///
/// Слова одни и те же, а переводы — на языке интерфейса: для английского
/// интерфейса это короткие толкования, как в учебном словаре.
@MainActor
enum StarterDeck {
    /// Свой набор у каждого изучаемого языка (P-67): английский — прежние
    /// файлы, у остальных в имени есть язык. Переводы — на языке интерфейса.
    static func resourceName(for language: AppLanguage = Loc.language,
                             target: StudyLanguage = StudyLanguageStore.storedCurrent) -> String {
        target == .english
            ? "starter-deck-\(language.rawValue)"
            : "starter-deck-\(target.rawValue)-\(language.rawValue)"
    }

    static func data(for language: AppLanguage = Loc.language,
                     target: StudyLanguage = StudyLanguageStore.storedCurrent) -> Data? {
        // Нет перевода на язык интерфейса — берём русский: для изучаемых
        // языков кроме английского он есть всегда.
        let url = Bundle.main.url(forResource: resourceName(for: language, target: target),
                                  withExtension: "json")
            ?? Bundle.main.url(forResource: resourceName(for: .russian, target: target),
                               withExtension: "json")
        guard let url else {
            Log.warning(.app, "Стартовый набор не найден в ресурсах приложения", detail: target.rawValue)
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// Есть ли стартовый набор для изучаемого языка — иначе кнопку не показываем.
    static var isAvailable: Bool { data() != nil }

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
