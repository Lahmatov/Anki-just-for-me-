#if DEBUG
import SwiftUI
import SwiftData
import AJFMCore

/// Mock-данные для превью в Xcode Canvas (навык ios-architecture, правило 4).
///
/// База — в памяти, наполняется теми же данными, что UI-тесты: стартовый
/// набор, сериал из каталога с просмотренной серией и урок. Так превью
/// показывает экран «как у человека через неделю», а не пустой.
/// Только в отладочной сборке: в выпуск mock-данные не попадают.
@MainActor
enum PreviewData {
    /// База с данными — для большинства превью.
    static let container: ModelContainer = {
        let container = makeContainer()
        let context = container.mainContext
        StarterDeck.install(into: context)
        UITesting.installDemoShow(into: context)
        UITesting.installDemoLesson(into: context)
        try? context.save()
        return container
    }()

    /// Пустая база — для превью пустых состояний.
    static let emptyContainer: ModelContainer = makeContainer()

    static var context: ModelContext { container.mainContext }

    private static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: StudyLanguageStore.schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: StudyLanguageStore.schema, configurations: configuration)
        } catch {
            fatalError("Preview container failed to open: \(error)")
        }
    }

    private static func first<Model: PersistentModel>(_ type: Model.Type,
                                                     where predicate: (Model) -> Bool = { _ in true }) -> Model {
        let all = (try? context.fetch(FetchDescriptor<Model>())) ?? []
        guard let match = all.first(where: predicate) ?? all.first else {
            fatalError("Preview data has no \(Model.self)")
        }
        return match
    }

    // MARK: - Готовые объекты

    /// Набор слов (стартовый).
    static var deck: Deck { first(Deck.self) { !DeckRequest.lessonFolderNames.contains($0.folder?.name ?? "") } }
    /// Урок — набор в папке уроков.
    static var lessonDeck: Deck { first(Deck.self) { DeckRequest.lessonFolderNames.contains($0.folder?.name ?? "") } }
    static var folder: Folder { first(Folder.self) }
    static var note: Note { first(Note.self) }
    static var card: Card { first(Card.self) }
    static var show: TrackedShow { first(TrackedShow.self) }

    /// Слова урока в виде данных — для тренажёров.
    static var lessonNotes: [NoteData] { lessonDeck.notes.map(\.asNoteData) }

    /// Серия сериала из демо-данных.
    static var episode: EpisodeContext {
        let show = show
        let info = show.episodes.first ?? EpisodeInfo(id: 1, season: 1, number: 1, name: "Pilot")
        return EpisodeContext(showID: show.tvmazeID, showName: show.name, episode: info)
    }

    static var lessonTopic: LessonTopic {
        LessonTopic(title: lessonDeck.name, terms: lessonDeck.notes.map(\.term))
    }

    /// План импорта из маленького набора — для экрана предпросмотра.
    static var importPlan: ImportPlan {
        let file = DeckFile(
            deck: DeckMeta(name: "Friends S01E03"),
            notes: [
                NoteData(term: "hang out", translation: "spend time together", partOfSpeech: .phrasalVerb,
                         example: "We hang out at Central Perk.", cloze: "We ___ ___ at Central Perk."),
                NoteData(term: "on a break", translation: "temporarily separated", partOfSpeech: .phrase,
                         example: "We were on a break!"),
            ])
        do {
            return try ImportService(context: context).makePlan(from: file)
        } catch {
            fatalError("Preview import plan failed: \(error)")
        }
    }

    static var catalogEntry: CatalogIndexEntry? { LocalCatalog.index()?.shows.first }
}

extension View {
    /// Окружение превью: база в памяти (с данными или пустая).
    func previewEnvironment(empty: Bool = false) -> some View {
        modelContainer(empty ? PreviewData.emptyContainer : PreviewData.container)
    }
}
#endif
