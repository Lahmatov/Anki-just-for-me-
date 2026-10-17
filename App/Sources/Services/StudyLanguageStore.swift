import Foundation
import Observation
import SwiftData
import AJFMCore

/// Какой язык учим сейчас и база этого языка (P-67).
///
/// Отдельная база на язык, а не поле «язык» у набора: очередь, серия,
/// статистика и карта читают базу целиком, и фильтр пришлось бы протянуть
/// в каждую выборку — забытый где-то фильтр смешал бы португальские
/// карточки с английскими. С отдельной базой смешать нечего.
@Observable
@MainActor
final class StudyLanguageStore {
    static let shared = StudyLanguageStore()

    private(set) var current: StudyLanguage
    @ObservationIgnored private var containers: [StudyLanguage: ModelContainer] = [:]

    private init() {
        current = StudyLanguage.stored(UserDefaults.standard.string(forKey: SettingsKey.studyLanguage))
    }

    /// Переключиться. Экраны пересоздаются с базой и ключами нового языка;
    /// прежняя база остаётся как есть — вернёшься, и всё на месте.
    func switchTo(_ language: StudyLanguage) {
        guard language != current else { return }
        UserDefaults.standard.set(language.rawValue, forKey: SettingsKey.studyLanguage)
        StudyShow.invalidate()
        current = language
        Log.info(.app, "Изучаемый язык", detail: language.rawValue)
        AnalyticsService.track(.studyLanguageSwitched(to: language))
    }

    static let schema = Schema([
        Folder.self, Deck.self, Note.self, Card.self, Review.self,
        RetellSession.self, UsageEntry.self, RewardContractEntity.self,
        ProgressSnapshot.self, TrackedShow.self,
    ])

    /// База языка; открывается один раз и дальше держится открытой —
    /// переключение туда и обратно мгновенное.
    func container(for language: StudyLanguage) -> ModelContainer {
        if let open = containers[language] { return open }
        // В UI-тестах база в памяти: каждый прогон — как первая установка.
        let inMemory = UITesting.isActive
        let configuration: ModelConfiguration
        if let name = language.storeName {
            configuration = ModelConfiguration(name, schema: Self.schema, isStoredInMemoryOnly: inMemory)
        } else {
            // Английский — в базе по умолчанию, где всё, что было до языков.
            configuration = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: inMemory)
        }
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Self.schema, configurations: configuration)
        } catch {
            // Без базы приложению делать нечего; так же вёл себя и
            // `.modelContainer(for:)`, только молча.
            fatalError("Model container failed to open: \(error)")
        }
        containers[language] = container
        return container
    }

    var currentContainer: ModelContainer { container(for: current) }

    /// Текущий язык для кода вне главного потока (озвучка, распознавание):
    /// прямо из UserDefaults, куда `switchTo` пишет до смены экранов.
    nonisolated static var storedCurrent: StudyLanguage {
        StudyLanguage.stored(UserDefaults.standard.string(forKey: SettingsKey.studyLanguage))
    }
}
