import XCTest
@testable import AJFMCore

final class ShowPathTests: XCTestCase {

    private func episode(_ season: Int, _ number: Int, total: Int = 15, started: Int = 0,
                         aired: Bool = true) -> ShowPathEpisode {
        ShowPathEpisode(key: EpisodeKey(season: season, number: number), totalWords: total,
                        startedWords: started, aired: aired)
    }

    // MARK: - Серия

    func testEpisodeIsDoneWhenAllItsWordsAreStarted() {
        XCTAssertTrue(episode(1, 1, total: 15, started: 15).isDone)
        XCTAssertFalse(episode(1, 1, total: 15, started: 14).isDone)
    }

    func testEpisodeWithoutDeckIsNeverDone() {
        XCTAssertFalse(episode(1, 1, total: 0, started: 0).isDone)
        XCTAssertEqual(episode(1, 1, total: 0).fraction, 0)
    }

    func testStartedIsClampedToTotal() {
        let odd = episode(1, 1, total: 10, started: 25)
        XCTAssertEqual(odd.startedWords, 10)
        XCTAssertEqual(odd.fraction, 1)
        XCTAssertEqual(episode(1, 1, total: 10, started: -3).startedWords, 0)
    }

    // MARK: - Путь

    func testEpisodesAreSortedAndDeduplicated() {
        let path = ShowPath(name: "X", episodes: [episode(2, 1), episode(1, 2), episode(1, 1), episode(1, 2)])
        XCTAssertEqual(path.episodes.map(\.code), ["S01E01", "S01E02", "S02E01"])
    }

    func testSpecialsAreLeftOut() {
        let path = ShowPath(name: "X", episodes: [episode(0, 1), episode(1, 1)])
        XCTAssertEqual(path.episodes.map(\.code), ["S01E01"])
    }

    func testEachSeasonEndsWithABigStop() {
        let path = ShowPath(name: "X", episodes: [episode(1, 1), episode(1, 2), episode(2, 1)])
        XCTAssertEqual(path.nodes.map(\.id), ["e1x1", "e1x2", "s1", "e2x1", "s2"])
    }

    func testSeasonIsDoneWhenAllItsEpisodesAre() {
        let path = ShowPath(name: "X", episodes: [
            episode(1, 1, started: 15), episode(1, 2, started: 15), episode(2, 1, started: 3)])
        XCTAssertTrue(path.isSeasonDone(1))
        XCTAssertFalse(path.isSeasonDone(2))
        XCTAssertEqual(path.completedSeasons, [1])
        XCTAssertFalse(path.isSeasonDone(7), "сезона без серий нет — и пройти его нельзя")
    }

    func testCountsAndCurrent() {
        let path = ShowPath(name: "X", episodes: [
            episode(1, 1, started: 15), episode(1, 2, started: 2), episode(1, 3)])
        XCTAssertEqual(path.doneCount, 1)
        XCTAssertEqual(path.total, 3)
        XCTAssertEqual(path.current?.code, "S01E02")
    }

    func testUnairedEpisodesAreNotCurrent() {
        let path = ShowPath(name: "X", episodes: [episode(1, 1, started: 15), episode(1, 2, aired: false)])
        XCTAssertNil(path.current)
    }

    func testEmptyPath() {
        let path = ShowPath(name: "X", episodes: [])
        XCTAssertEqual(path.nodes, [])
        XCTAssertNil(path.current)
        XCTAssertEqual(path.doneCount, 0)
    }

    // MARK: - Праздник сезона

    func testFirstOpenDoesNotCelebrateOldSeasons() {
        let path = ShowPath(name: "X", episodes: [episode(1, 1, started: 15)])
        XCTAssertNil(path.seasonToCelebrate(celebrated: nil))
    }

    func testNewlyFinishedSeasonIsCelebratedOnce() {
        let path = ShowPath(name: "X", episodes: [episode(1, 1, started: 15), episode(2, 1, started: 15)])
        XCTAssertEqual(path.seasonToCelebrate(celebrated: [1]), 2)
        XCTAssertNil(path.seasonToCelebrate(celebrated: [1, 2]))
    }
}
