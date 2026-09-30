import Foundation
import SwiftData
import AJFMCore

/// Готовые наборы к сериалам, вшитые в приложение (`BundledCatalog`).
///
/// Без сервера и без ИИ: слова собраны заранее, набор к серии добавляется
/// мгновенно и бесплатно. Файлы — в ресурсах, по одному на сериал, и
/// читаются только когда открыт этот сериал: все пятьдесят сразу — это
/// мегабайты, которые на главном экране не нужны.
@MainActor
enum LocalCatalog {
    private static var cachedIndex: CatalogIndex?
    /// Разобранные файлы сериалов: карта и «Сегодня» спрашивают один и тот же
    /// сериал при каждом обновлении, а файл — сотни килобайт JSON.
    private static var cachedShows: [String: CatalogShowFile] = [:]

    static func index(bundle: Bundle = .main) -> CatalogIndex? {
        if let cachedIndex { return cachedIndex }
        guard let url = bundle.url(forResource: "catalog-index", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            let index = try BundledCatalog.decodeIndex(data)
            cachedIndex = index
            return index
        } catch {
            Log.failure(.app, "Каталог в приложении не читается", error)
            return nil
        }
    }

    static func show(_ entry: CatalogIndexEntry, bundle: Bundle = .main) -> CatalogShowFile? {
        if let cached = cachedShows[entry.resource] { return cached }
        guard let url = bundle.url(forResource: entry.resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            let show = try BundledCatalog.decodeShow(data)
            cachedShows[entry.resource] = show
            return show
        } catch {
            Log.failure(.app, "Сериал из каталога не читается: \(entry.name)", error)
            return nil
        }
    }

    /// Источник набора — по нему видно, что серия уже добавлена.
    static func source(show: CatalogShowFile, episode: CatalogEpisode) -> String {
        "\(show.name) \(episode.code)"
    }

    /// Какие серии этого сериала уже есть среди наборов.
    static func installedSources(in context: ModelContext) -> Set<String> {
        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        return Set(decks.compactMap(\.source))
    }

    /// Добавить набор к серии. Слова, которые уже есть в базе, не дублируются —
    /// это решает импорт, как для любого другого набора.
    @discardableResult
    static func install(episode: CatalogEpisode, of show: CatalogShowFile,
                        language: AppLanguage = Loc.language,
                        into context: ModelContext) throws -> ImportResult {
        let file = BundledCatalog.deckFile(show: show, episode: episode, language: language)
        let service = ImportService(context: context)
        let result = try service.apply(try service.makePlan(from: file))
        Log.info(.importing, "Набор из каталога добавлен",
                 detail: "\(show.name) \(episode.code), слов: \(result.addedNotes)")
        return result
    }
}
