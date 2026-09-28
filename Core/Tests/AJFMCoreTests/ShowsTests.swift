import XCTest
@testable import AJFMCore

final class EpisodeRefTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Loc.language = .russian
    }

    override func tearDown() {
        Loc.language = .russian
        super.tearDown()
    }

    private func ref(_ text: String) -> EpisodeRef? { EpisodeRef.parse(text) }

    func testCommonNotations() {
        let expected = EpisodeRef(show: "Friends", season: 1, episode: 3)
        XCTAssertEqual(ref("Friends 1x03"), expected)
        XCTAssertEqual(ref("Friends S01E03"), expected)
        XCTAssertEqual(ref("friends s1e3")?.season, 1)
        XCTAssertEqual(ref("Friends s1 e3"), expected)
        XCTAssertEqual(ref("Friends, season 1 episode 3"), expected)
        XCTAssertEqual(ref("Friends temporada 1 episódio 3"), expected)
    }

    func testRussianNotations() {
        let expected = EpisodeRef(show: "Друзья", season: 2, episode: 5)
        XCTAssertEqual(ref("Друзья 2 сезон 5 серия"), expected)
        XCTAssertEqual(ref("Друзья сезон 2 серия 5"), expected)
    }

    func testShowNamesWithDigitsAndDashes() {
        XCTAssertEqual(ref("9-1-1 S02E03"), EpisodeRef(show: "9-1-1", season: 2, episode: 3))
        XCTAssertEqual(ref("The X-Files 3x04")?.show, "The X-Files")
        XCTAssertEqual(ref("How I Met Your Mother - 2x05")?.show, "How I Met Your Mother")
    }

    func testTrailingWordsAreIgnored() {
        XCTAssertEqual(ref("Friends 1x03 слова для пересказа")?.episode, 3)
    }

    func testNotAnEpisode() {
        XCTAssertNil(ref("слова для собеседования в IT"))
        XCTAssertNil(ref(""))
        XCTAssertNil(ref("S01E03"), "без названия сериала это не серия")
        XCTAssertNil(ref("Friends 0x00"))
    }

    func testValidatingInitRejectsGarbage() {
        XCTAssertNil(EpisodeRef(validatingShow: "  ", season: 1, episode: 1))
        XCTAssertNil(EpisodeRef(validatingShow: "X", season: 0, episode: 1))
        XCTAssertNil(EpisodeRef(validatingShow: "X", season: 1, episode: 0))
        XCTAssertNil(EpisodeRef(validatingShow: "X", season: 100, episode: 1))
        XCTAssertEqual(EpisodeRef(validatingShow: " Lost ", season: 4, episode: 5)?.show, "Lost")
    }

    func testCodeAndNames() {
        let episode = EpisodeRef(show: "Friends", season: 1, episode: 3)
        XCTAssertEqual(episode.code, "S01E03")
        XCTAssertEqual(EpisodeRef(show: "X", season: 12, episode: 104).code, "S12E104")
        XCTAssertEqual(episode.deckName(title: "The One with the Thumb"),
                       "S01E03 · The One with the Thumb")
        XCTAssertEqual(episode.deckName(title: "  "), "S01E03")
        XCTAssertEqual(episode.deckName(title: nil), "S01E03")
        XCTAssertEqual(episode.folderPath, ["Сериалы", "Friends", "Сезон 1"])
        XCTAssertEqual(ImportPlan.folderPath(from: episode.folder), episode.folderPath)
    }
}

final class TVMazeTests: XCTestCase {

    func testSearchURLEncodesTheName() throws {
        let url = try XCTUnwrap(TVMaze.showSearchURL("How I Met Your Mother"))
        XCTAssertEqual(url.absoluteString,
                       "https://api.tvmaze.com/singlesearch/shows?q=How%20I%20Met%20Your%20Mother")
        XCTAssertNil(TVMaze.showSearchURL("   "))
    }

    func testEpisodeURL() {
        XCTAssertEqual(TVMaze.episodeURL(showID: 431, season: 1, episode: 3)?.absoluteString,
                       "https://api.tvmaze.com/shows/431/episodebynumber?season=1&number=3")
    }

    func testParsesShowWithPoster() {
        let data = Data("""
        { "id": 431, "name": "Friends",
          "image": { "medium": "http://static.tvmaze.com/uploads/images/medium_portrait/41/104550.jpg",
                     "original": "https://static.tvmaze.com/uploads/images/original_untouched/41/104550.jpg" } }
        """.utf8)
        let show = TVMaze.parseShow(data)
        XCTAssertEqual(show?.id, 431)
        XCTAssertEqual(show?.name, "Friends")
        // http приводится к https — иначе iOS не загрузит картинку.
        XCTAssertEqual(show?.posterURL,
                       "https://static.tvmaze.com/uploads/images/medium_portrait/41/104550.jpg")
    }

    func testShowWithoutImageHasNoPoster() {
        let show = TVMaze.parseShow(Data(#"{ "id": 1, "name": "X", "image": null }"#.utf8))
        XCTAssertEqual(show?.id, 1)
        XCTAssertNil(show?.posterURL)
    }

    func testBrokenOrForeignShowResponses() {
        XCTAssertNil(TVMaze.parseShow(Data("not json".utf8)))
        XCTAssertNil(TVMaze.parseShow(Data("[]".utf8)))
        XCTAssertNil(TVMaze.parseShow(Data(#"{ "name": "no id" }"#.utf8)))
        XCTAssertNil(TVMaze.parseShow(Data(#"{ "id": 1, "name": "" }"#.utf8)))
    }

    func testEpisodeTitle() {
        XCTAssertEqual(TVMaze.parseEpisodeTitle(Data(#"{ "name": " The One with the Thumb " }"#.utf8)),
                       "The One with the Thumb")
        XCTAssertNil(TVMaze.parseEpisodeTitle(Data(#"{ "name": "" }"#.utf8)))
        XCTAssertNil(TVMaze.parseEpisodeTitle(Data(#"{ "status": 404 }"#.utf8)))
    }
}
