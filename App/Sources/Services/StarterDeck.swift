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
        // Перевод — на язык интерфейса, кроме случая «учу португальский с
        // португальским интерфейсом». Нет такого файла — английский, затем русский:
        // у изучаемых языков кроме английского эти два есть всегда.
        guard let url = url(for: language, target: target) else {
            Log.warning(.app, "Стартовый набор не найден в ресурсах приложения", detail: target.rawValue)
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private static func url(for language: AppLanguage, target: StudyLanguage) -> URL? {
        let candidates = [target.translationLanguage(for: language), .english, .russian]
        return candidates.lazy.compactMap {
            Bundle.main.url(forResource: resourceName(for: $0, target: target), withExtension: "json")
        }.first
    }

    /// Есть ли стартовый набор для изучаемого языка — иначе кнопку не показываем.
    /// Спрашивается из body экранов, поэтому только ищет файл, не читая его.
    static var isAvailable: Bool {
        url(for: Loc.language, target: StudyLanguageStore.storedCurrent) != nil
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
