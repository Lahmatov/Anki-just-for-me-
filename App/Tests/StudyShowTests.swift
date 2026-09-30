import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

/// Карта по сериалу на настоящей базе. Правила пути — в ShowPathTests ядра.
@MainActor
final class StudyShowTests: XCTestCase {

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.studyShow)
        StudyShow.invalidate()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.studyShow)
    }

    private func install(show: String, season: Int = 1, episode: Int, words: Int,
                         into context: ModelContext) throws {
        let notes = (1...words).map { NoteData(term: "\(show) \(episode) w\($0)", translation: "слово \($0)") }
        let file = DeckFile(deck: DeckMeta(name: "S0\(season)E0\(episode)",
                                           source: RecapPlan.deckSource(showName: show, season: season,
                                                                        episode: episode)),
                            notes: notes)
        let importer = ImportService(context: context)
        try importer.apply(try importer.makePlan(from: file))
    }

    // MARK: - Разбор источника

    func testEpisodeCodeParsesOnlyRealCodes() {
        XCTAssertEqual(StudyShow.episodeKey(fromCode: "s01e03"), EpisodeKey(season: 1, number: 3))
        XCTAssertEqual(StudyShow.episodeKey(fromCode: "S10E22"), EpisodeKey(season: 10, number: 22))
        XCTAssertNil(StudyShow.episodeKey(fromCode: "pilot"))
        XCTAssertNil(StudyShow.episodeKey(fromCode: "S00E00"))
        XCTAssertNil(StudyShow.episodeKey(fromCode: "S01"))
    }

    // MARK: - Слова по сериям

    func testDeckStatsCountStartedWordsPerEpisode() throws {
        let context = try TestDB.makeContext()
        try install(show: "Lost", episode: 1, words: 4, into: context)
        try install(show: "Lost", episode: 2, words: 3, into: context)
        // Две карточки первого слова первой серии — одно начатое слово.
        let deck = try XCTUnwrap(StudyShow.deck(for: EpisodeKey(season: 1, number: 1), showName: "Lost", in: context))
        for card in deck.notes.first?.cards ?? [] { card.state = .learning }
        try context.save()

        let stats = StudyShow.deckStats(showName: "Lost", in: context)
        XCTAssertEqual(stats[EpisodeKey(season: 1, number: 1)]?.total, 4)
        XCTAssertEqual(stats[EpisodeKey(season: 1, number: 1)]?.started, 1)
        XCTAssertEqual(stats[EpisodeKey(season: 1, number: 2)]?.started, 0)
    }

    func testOtherShowsDecksDoNotLeakIn() throws {
        let context = try TestDB.makeContext()
        try install(show: "Lost", episode: 1, words: 2, into: context)
        try install(show: "Lost Girl", episode: 1, words: 5, into: context)
        XCTAssertEqual(StudyShow.deckStats(showName: "Lost", in: context)[EpisodeKey(season: 1, number: 1)]?.total, 2,
                       "«Lost Girl» — другой сериал, хоть и начинается так же")
    }

    func testShowNameMatchesWithoutCase() throws {
        let context = try TestDB.makeContext()
        try install(show: "The Office", episode: 1, words: 2, into: context)
        XCTAssertNotNil(StudyShow.deck(for: EpisodeKey(season: 1, number: 1), showName: "the office", in: context))
    }

    // MARK: - Выбор сериала

    func testNoShowNoPath() throws {
        XCTAssertNil(StudyShow.path(in: try TestDB.makeContext()))
    }

    func testStartingACatalogShowAddsItsFirstEpisode() throws {
        let context = try TestDB.makeContext()
        let entry = try XCTUnwrap(LocalCatalog.index()?.shows.first, "каталог должен быть в сборке")
        try StudyShow.start(catalog: entry, in: context)

        XCTAssertTrue(StudyShow.isCurrent(entry.name))
        let path = try XCTUnwrap(StudyShow.path(in: context))
        XCTAssertEqual(path.name, entry.name)
        XCTAssertEqual(path.episodes.first?.hasDeck, true, "первая серия уже со словами")
        XCTAssertEqual(path.current?.key, EpisodeKey(season: 1, number: 1))
        XCTAssertTrue(path.episodes.dropFirst().allSatisfy(\.catalogWords), "остальные — готовые слова")
    }

    func testStartingTwiceDoesNotDuplicateTheFirstEpisode() throws {
        let context = try TestDB.makeContext()
        let entry = try XCTUnwrap(LocalCatalog.index()?.shows.first)
        try StudyShow.start(catalog: entry, in: context)
        try StudyShow.start(catalog: entry, in: context)
        let decks = try context.fetch(FetchDescriptor<Deck>())
        XCTAssertEqual(decks.count, 1)
    }

    func testCatalogWordsInstallFromTheMap() throws {
        let context = try TestDB.makeContext()
        let entry = try XCTUnwrap(LocalCatalog.index()?.shows.first)
        StudyShow.choose(entry.name)
        try StudyShow.installCatalogWords(for: EpisodeKey(season: 1, number: 2), showName: entry.name, in: context)
        let path = try XCTUnwrap(StudyShow.path(in: context))
        XCTAssertTrue(path.episodes.first { $0.key == EpisodeKey(season: 1, number: 2) }?.hasDeck ?? false)
    }

    func testUnknownShowWithoutEpisodesHasNoPath() throws {
        StudyShow.choose("A Show Nobody Has")
        XCTAssertNil(StudyShow.path(in: try TestDB.makeContext()))
    }

    // MARK: - Кеш

    func testCachedPathRefreshesAfterSave() throws {
        let context = try TestDB.makeContext()
        let entry = try XCTUnwrap(LocalCatalog.index()?.shows.first)
        try StudyShow.start(catalog: entry, in: context)
        let before = try XCTUnwrap(StudyShow.path(in: context))
        XCTAssertEqual(before.episodes.first?.startedWords, 0)

        // Слова первой серии начаты и сохранены — карта обязана это увидеть.
        for card in try context.fetch(FetchDescriptor<Card>()) { card.state = .learning }
        try context.save()

        let after = try XCTUnwrap(StudyShow.path(in: context))
        XCTAssertEqual(after.episodes.first?.isDone, true)
    }
}
