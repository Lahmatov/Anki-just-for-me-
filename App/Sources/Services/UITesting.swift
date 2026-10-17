import Foundation
import SwiftData
import AJFMCore

/// Режим UI-тестов (`-ui-testing` в аргументах запуска).
///
/// Тест должен начинаться с чистого листа и сразу видеть главный экран:
/// база — в памяти, настройки сброшены, заставка и знакомство пропущены.
/// Иначе каждый прогон зависел бы от предыдущего и от анимации запуска.
enum UITesting {
    static let flag = "-ui-testing"

    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(flag) }

    /// `-ui-demo`: сразу со стартовым набором — для скриншотов экранов,
    /// где пустая база показала бы только заглушки.
    static var wantsDemoData: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("-ui-demo")
    }

    /// `-ui-demo-show`: вдобавок отслеживаемый сериал из каталога с двумя
    /// сериями и словами первой — чтобы карта, серия и Recap открывались
    /// без сети: TVMaze в тестах недоступен или медленный.
    static var wantsDemoShow: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("-ui-demo-show")
    }

    /// `-ui-onboarding`: знакомство показывается, как на первой установке, —
    /// для теста главного пути «запуск → знакомство → первое занятие».
    static var wantsOnboarding: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("-ui-onboarding")
    }

    /// `-ui-demo-lesson`: урок в папке уроков — с глаголами, примерами и
    /// пропусками, чтобы открывались все тренажёры, тест и спряжение (P-69).
    static var wantsDemoLesson: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("-ui-demo-lesson")
    }

    @MainActor
    static func installDemoLesson(into context: ModelContext) {
        let notes = [
            NoteData(term: "go", translation: "move to another place", partOfSpeech: .verb,
                     example: "We go to Lisbon every summer.", cloze: "We ___ to Lisbon every summer."),
            NoteData(term: "travel", translation: "make a journey", partOfSpeech: .verb,
                     example: "They travel by train.", cloze: "They ___ by train."),
            NoteData(term: "book a flight", translation: "reserve a plane ticket", partOfSpeech: .phrase,
                     example: "I booked a flight to Rome.", cloze: "I ___ a flight to Rome."),
            NoteData(term: "get by", translation: "manage with what you have", partOfSpeech: .phrasalVerb,
                     example: "I can get by in Italian."),
            NoteData(term: "the luggage", translation: "bags you take on a trip", partOfSpeech: .noun,
                     example: "Where is the luggage?"),
        ]
        let file = DeckFile(deck: DeckMeta(name: "Lesson 1: Travel", folder: DeckRequest.lessonFolder),
                            notes: notes)
        let importer = ImportService(context: context)
        guard let plan = try? importer.makePlan(from: file) else { return }
        _ = try? importer.apply(plan)
    }

    /// До первого экрана: прошлый прогон не должен оставить ни настроек, ни языка.
    static func prepare() {
        guard isActive, let domain = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }

    @MainActor
    static func installDemoShow(into context: ModelContext) {
        guard let entry = LocalCatalog.index()?.shows.first else { return }
        let episodes = [
            EpisodeInfo(id: 1, season: 1, number: 1, name: "Pilot", airdate: "2000-01-01",
                        summary: "Friends meet in a coffee shop."),
            EpisodeInfo(id: 2, season: 1, number: 2, name: "The Second One", airdate: "2000-01-08"),
        ]
        let show = TrackedShow(show: TVMaze.Show(id: 1, name: entry.name, premieredYear: entry.year),
                               episodes: episodes)
        show.watched = [EpisodeKey(season: 1, number: 1)]
        context.insert(show)
        _ = try? StudyShow.start(catalog: entry, in: context)
        try? context.save()
    }
}
