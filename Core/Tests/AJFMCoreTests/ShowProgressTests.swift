import XCTest
@testable import AJFMCore

final class TVMazeEpisodesTests: XCTestCase {

    func testSearchReturnsShowsInOrderWithYears() {
        let data = Data("""
        [ { "score": 0.9, "show": { "id": 431, "name": "Friends", "premiered": "1994-09-22",
            "image": { "medium": "https://static.tvmaze.com/a.jpg" } } },
          { "score": 0.5, "show": { "id": 5000, "name": "Friends", "premiered": null, "image": null } },
          { "score": 0.4, "show": { "name": "без id" } },
          { "score": 0.3, "show": { "id": 431, "name": "Friends" } } ]
        """.utf8)
        let shows = TVMaze.parseSearch(data)
        XCTAssertEqual(shows.map(\.id), [431, 5000], "битые и повторы отброшены")
        XCTAssertEqual(shows[0].premieredYear, 1994)
        XCTAssertNil(shows[1].premieredYear)
        XCTAssertNil(shows[1].posterURL)
    }

    func testSearchOnGarbageIsEmpty() {
        XCTAssertEqual(TVMaze.parseSearch(Data("{}".utf8)), [])
        XCTAssertEqual(TVMaze.parseSearch(Data("oops".utf8)), [])
        XCTAssertNil(TVMaze.searchURL("  "))
        XCTAssertEqual(TVMaze.searchURL("The Office")?.absoluteString,
                       "https://api.tvmaze.com/search/shows?q=The%20Office")
    }

    func testEpisodesAreSortedAndSpecialsSkipped() {
        let data = Data("""
        [ { "id": 3, "season": 1, "number": 2, "name": "Two", "airdate": "1994-09-29",
            "runtime": 30, "summary": "<p>Ross <b>finds out</b>.</p>" },
          { "id": 1, "season": 1, "number": 1, "name": "One", "airdate": "", "summary": null },
          { "id": 9, "season": 1, "number": null, "name": "Special" },
          { "id": 8, "season": 0, "number": 1, "name": "Pilot extra" },
          { "id": 4, "season": 1, "number": 2, "name": "Duplicate" } ]
        """.utf8)
        let episodes = TVMaze.parseEpisodes(data)
        XCTAssertEqual(episodes.map(\.id), [1, 3])
        XCTAssertNil(episodes[0].airdate, "пустая дата — неизвестна")
        XCTAssertEqual(episodes[0].summary, "")
        XCTAssertEqual(episodes[1].summary, "Ross finds out.")
        XCTAssertEqual(episodes[1].runtime, 30)
        XCTAssertEqual(episodes[1].title, "S01E02 · Two")
    }

    func testHTMLBecomesPlainText() {
        XCTAssertEqual(
            TVMaze.plainText(fromHTML: "<p>Monica &amp; Rachel&#39;s   <i>big</i> day.</p><p>Next</p>"),
            "Monica & Rachel's big day.\nNext")
        XCTAssertEqual(TVMaze.plainText(fromHTML: "a&amp;lt;b"), "a&lt;b",
                       "сущность внутри сущности не раскодируется дважды")
        XCTAssertEqual(TVMaze.plainText(fromHTML: ""), "")
    }
}

final class ShowProgressTests: XCTestCase {

    private func episode(_ season: Int, _ number: Int, aired: String? = "2020-01-01") -> EpisodeInfo {
        EpisodeInfo(id: season * 100 + number, season: season, number: number,
                    name: "E\(number)", airdate: aired)
    }

    private var episodes: [EpisodeInfo] {
        [episode(1, 1), episode(1, 2), episode(1, 3), episode(2, 1), episode(2, 2),
         episode(2, 3, aired: "2099-01-01")]
    }

    private func progress(_ watched: [EpisodeKey]) -> ShowProgress {
        ShowProgress(episodes: episodes.shuffled(), watched: Set(watched), today: "2026-09-28")
    }

    private func key(_ s: Int, _ n: Int) -> EpisodeKey { EpisodeKey(season: s, number: n) }

    func testKeyRoundTripsAndRejectsGarbage() {
        XCTAssertEqual(EpisodeKey(raw: "2x13"), key(2, 13))
        XCTAssertEqual(key(2, 13).raw, "2x13")
        XCTAssertEqual(key(2, 13).code, "S02E13")
        XCTAssertNil(EpisodeKey(raw: "0x1"))
        XCTAssertNil(EpisodeKey(raw: "abc"))
        XCTAssertNil(EpisodeKey(raw: "1x"))
    }

    func testNothingWatchedStartsFromTheFirst() {
        let p = progress([])
        XCTAssertEqual(p.nextEpisode?.key, key(1, 1))
        XCTAssertEqual(p.watchedCount, 0)
        XCTAssertEqual(p.fraction, 0)
    }

    func testNextFollowsTheLastWatchedEvenWithAGap() {
        // Пропустил 1x2 сознательно — дальше 2x1, а не возврат назад.
        XCTAssertEqual(progress([key(1, 1), key(1, 3)]).nextEpisode?.key, key(2, 1))
    }

    func testFutureEpisodesAreNotNextAndDoNotCount() {
        let all = [key(1, 1), key(1, 2), key(1, 3), key(2, 1), key(2, 2)]
        let p = progress(all)
        XCTAssertNil(p.nextEpisode, "невышедшая серия не «следующая»")
        XCTAssertEqual(p.airedCount, 5)
        XCTAssertEqual(p.fraction, 1)
    }

    func testWhenTheTailIsWatchedTheEarliestGapIsNext() {
        XCTAssertEqual(progress([key(2, 2)]).nextEpisode?.key, key(1, 1))
    }

    func testMarksForUnknownEpisodesDoNotInflateTheCount() {
        XCTAssertEqual(progress([key(1, 1), key(9, 9)]).watchedCount, 1)
    }

    func testSeasonsAreGroupedInOrder() {
        let seasons = progress([]).seasons
        XCTAssertEqual(seasons.map(\.number), [1, 2])
        XCTAssertEqual(seasons[0].episodes.map(\.number), [1, 2, 3])
    }

    func testMarkingUpToSkipsFutureEpisodes() {
        let marked = progress([]).markingUpTo(key(2, 3))
        XCTAssertEqual(marked.count, 5)
        XCTAssertFalse(marked.contains(key(2, 3)))
        XCTAssertEqual(progress([]).markingUpTo(key(1, 2)), [key(1, 1), key(1, 2)])
    }

    func testTogglingASeason() {
        let p = progress([key(1, 1)])
        let on = p.togglingSeason(1)
        XCTAssertEqual(on, [key(1, 1), key(1, 2), key(1, 3)])
        let off = ShowProgress(episodes: episodes, watched: on, today: "2026-09-28").togglingSeason(1)
        XCTAssertEqual(off, [])
    }

    func testSeasonWithOnlyFutureEpisodesIsNotWatched() {
        let p = ShowProgress(episodes: [episode(3, 1, aired: "2099-01-01")], watched: [],
                             today: "2026-09-28")
        XCTAssertFalse(p.isSeasonWatched(3))
    }

    func testEmptyShow() {
        let p = ShowProgress(episodes: [], watched: [key(1, 1)], today: "2026-09-28")
        XCTAssertNil(p.nextEpisode)
        XCTAssertEqual(p.fraction, 0, "без серий нет деления на ноль")
    }

    func testEpisodeWithoutDateCountsAsAired() {
        XCTAssertTrue(episode(1, 1, aired: nil).isAired(today: "2026-09-28"))
        XCTAssertTrue(episode(1, 1, aired: "2026-09-28").isAired(today: "2026-09-28"))
        XCTAssertFalse(episode(1, 1, aired: "2026-09-29").isAired(today: "2026-09-28"))
    }

    func testTodayFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21
        XCTAssertEqual(ShowProgress.today(date, calendar: calendar), "2026-09-21")
    }
}
