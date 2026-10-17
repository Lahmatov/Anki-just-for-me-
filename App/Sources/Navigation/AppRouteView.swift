import SwiftUI
import SwiftData
import AJFMCore

/// Экран для маршрута. Записи SwiftData достаются по идентификатору из
/// базы текущего языка; запись успели удалить — честное «нет», а не падение.
struct AppRouteView: View {
    let route: AppRoute

    @Environment(\.modelContext) private var context

    var body: some View {
        switch route {
        case .rewards: RewardsView()
        case .stats: StatsView()
        case .difficultCards: DifficultCardsView()
        case .journeyMap: JourneyMapView()
        case .lessonsMap: LessonsMapView()

        case .search: SearchView()
        case .note(let id): model(id, as: Note.self) { NoteDetailView(note: $0) }
        case .deck(let id): model(id, as: Deck.self) { DeckDetailView(deck: $0) }
        case .folder(let id):
            model(id, as: Folder.self) { folder in
                FolderContentsView(folder: folder).navigationTitle(folder.name)
            }
        case .review(let deckID, let limit):
            if let deckID {
                model(deckID, as: Deck.self) { ReviewSessionView(deck: $0, limit: limit) }
            } else {
                ReviewSessionView(deck: nil, limit: limit)
            }

        case .lesson(let id): model(id, as: Deck.self) { LessonHubView(deck: $0) }
        case .lessonDrill(let id, let mode):
            model(id, as: Deck.self) { LessonDrillView(notes: LessonLibrary.notes(of: $0), mode: mode) }
        case .conjugation(let verbs): ConjugationDrillView(verbs: verbs)
        case .lessonQuiz(let id): model(id, as: Deck.self) { LessonQuizView(deck: $0) }
        case .lessonSpeak(let id):
            model(id, as: Deck.self) { LessonSpeakView(deck: $0, notes: LessonLibrary.notes(of: $0)) }
        case .lessonChat(let id, let retelling):
            model(id, as: Deck.self) { deck in
                EpisodeDiscussionView(lesson: LessonTopic(deck: deck, notes: LessonLibrary.notes(of: deck)),
                                      retelling: retelling)
            }

        case .show(let id): model(id, as: TrackedShow.self) { ShowDetailView(show: $0) }
        case .episode(let showID, let episode):
            model(showID, as: TrackedShow.self) { EpisodeView(show: $0, episode: episode) }
        case .episodeRecap(let showID, let episode):
            model(showID, as: TrackedShow.self) { EpisodeRecapView(show: $0, episode: episode) }
        case .retell(let episode): RetellView(episode: episode)
        case .episodeChat(let episode, let retelling):
            EpisodeDiscussionView(episode: episode, retelling: retelling)
        case .catalogShow(let resource):
            if let entry = LocalCatalog.index()?.shows.first(where: { $0.resource == resource }) {
                CatalogShowView(entry: entry)
            } else {
                missing
            }
        case .minimalPairs: MinimalPairsView()
        case .youglish(let word): YouGlishScreen(word: word)

        case .account: AccountView()
        case .plus: PlusView()
        case .aiKeys: AIKeysView()
        case .cloudBackup: CloudBackupView()
        case .log: LogView()
        case .serverData: ServerDataView()
        case .privacy: PrivacyView()
        case .sellerInfo: SellerInfoView()
        case .legal(let kind): LegalDocumentView(kind: kind)
        case .help: MonchikHelpView()
        case .whySeries: WhySeriesView()
        case .supportTicket: SupportTicketView()
        case .supportTickets: SupportTicketsView()
        }
    }

    /// Запись по идентификатору; нет её — экран «не найдено».
    @ViewBuilder
    private func model<Model: PersistentModel, Content: View>(
        _ id: PersistentIdentifier, as type: Model.Type, @ViewBuilder content: (Model) -> Content
    ) -> some View {
        if let found: Model = lookup(id) {
            content(found)
        } else {
            missing
        }
    }

    /// `model(for:)` не годится: для неизвестного идентификатора он отдаёт
    /// пустую запись-призрак, а не nil. Запись, которую показывали, уже
    /// в контексте; удалённую и сохранённую (другое окно на iPad или Duo)
    /// там не найти — и в базе тоже.
    private func lookup<Model: PersistentModel>(_ id: PersistentIdentifier) -> Model? {
        if let registered: Model = context.registeredModel(for: id) {
            return registered.isDeleted ? nil : registered
        }
        return (try? context.fetch(FetchDescriptor<Model>()))?.first { $0.persistentModelID == id }
    }

    private var missing: some View {
        ContentUnavailableView(tr("Уже удалено", "Já foi apagado", "Already deleted"),
                               systemImage: "questionmark.folder",
                               description: Text(tr("Этой записи больше нет.", "Este registo já não existe.",
                                                    "This item no longer exists.")))
    }
}
