import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

/// Отметки просмотра — единственное, что человек вводит руками и чего
/// не восстановить из TVMaze. Проверяем, что они не теряются и не двоятся.
@MainActor
final class ShowServiceTests: XCTestCase {

    private let friends = TVMaze.Show(id: 431, name: "Friends", posterURL: nil, premieredYear: 1994)

    private func episodes(_ count: Int, season: Int = 1) -> [EpisodeInfo] {
        (1...count).map {
            EpisodeInfo(id: season * 100 + $0, season: season, number: $0, name: "E\($0)",
                        airdate: "2000-01-01")
        }
    }

    private func key(_ s: Int, _ n: Int) -> EpisodeKey { EpisodeKey(season: s, number: n) }

    func testStoringTheSameShowTwiceKeepsOneAndItsMarks() throws {
        let service = ShowService(context: try TestDB.makeContext())
        let show = try service.store(friends, episodes: episodes(3))
        service.setWatched(key(1, 1), true, in: show)

        try service.store(friends, episodes: episodes(3) + episodes(2, season: 2))

        XCTAssertEqual(service.all().count, 1)
        XCTAssertEqual(service.all().first?.episodes.count, 5)
        XCTAssertEqual(service.all().first?.watched, [key(1, 1)])
    }

    func testWatchedMarksPersistAndToggle() throws {
        let context = try TestDB.makeContext()
        let service = ShowService(context: context)
        let show = try service.store(friends, episodes: episodes(3))
        service.setWatched(key(1, 2), true, in: show)
        service.setWatched(key(1, 3), true, in: show)
        service.setWatched(key(1, 2), false, in: show)

        let reloaded = try XCTUnwrap(ShowService(context: context).tracked(id: 431))
        XCTAssertEqual(reloaded.watched, [key(1, 3)])
        XCTAssertEqual(reloaded.watchedRaw, ["1x3"])
    }

    func testMarkUpToAndSeasonToggle() throws {
        let service = ShowService(context: try TestDB.makeContext())
        let show = try service.store(friends, episodes: episodes(3) + episodes(2, season: 2))
        service.markUpTo(key(2, 1), in: show)
        XCTAssertEqual(show.progress().watchedCount, 4)
        XCTAssertEqual(show.progress().nextEpisode?.key, key(2, 2))

        service.toggleSeason(1, in: show)
        XCTAssertEqual(show.watched, [key(2, 1)])
    }

    func testRemovingAShow() throws {
        let service = ShowService(context: try TestDB.makeContext())
        let show = try service.store(friends, episodes: episodes(2))
        service.remove(show)
        XCTAssertTrue(service.all().isEmpty)
    }

    func testRetoldEpisodesComeFromRetellSessions() throws {
        let context = try TestDB.makeContext()
        let service = ShowService(context: context)
        let show = try service.store(friends, episodes: episodes(3))
        let report = try JSONDecoder().decode(RetellReport.self, from: Data("""
        {"understanding": {"correct": [], "incorrect": [], "missed": [], "coverage": 0.5},
         "language": {"grammar": [], "vocabulary": [], "fluencyNote": null, "suggestedWords": []},
         "topPriorities": []}
        """.utf8))
        let session = RetellSession(episodeTitle: "x", transcript: "t", report: report,
                                    cost: 0, model: "m")
        session.showID = 431
        session.episodeKeyRaw = "1x2"
        context.insert(session)
        let other = RetellSession(episodeTitle: "y", transcript: "t", report: report,
                                  cost: 0, model: "m")
        context.insert(other)
        try context.save()

        XCTAssertEqual(service.retoldEpisodes(of: show), [key(1, 2)])
    }

    func testShowsSurviveBackupAndRestore() throws {
        let source = try TestDB.makeContext()
        let show = try ShowService(context: source).store(friends, episodes: episodes(3))
        ShowService(context: source).setWatched(key(1, 2), true, in: show)
        let backup = try ExportService(context: source).makeBackup()

        let target = try TestDB.makeContext()
        try RestoreService(context: target).restore(backup)

        let restored = try XCTUnwrap(ShowService(context: target).tracked(id: 431))
        XCTAssertEqual(restored.watched, [key(1, 2)])
        XCTAssertEqual(restored.episodes.count, 3)
    }

    func testOldBackupDoesNotWipeShows() throws {
        let context = try TestDB.makeContext()
        try ShowService(context: context).store(friends, episodes: episodes(1))
        try RestoreService(context: context).restore(BackupFile(exportedAt: Date(), decks: []))
        XCTAssertEqual(ShowService(context: context).all().count, 1)
    }

    func testEraseRemovesShows() throws {
        let context = try TestDB.makeContext()
        try ShowService(context: context).store(friends, episodes: episodes(1))
        try DataEraseService(context: context).eraseDatabase()
        XCTAssertTrue(ShowService(context: context).all().isEmpty)
    }
}
