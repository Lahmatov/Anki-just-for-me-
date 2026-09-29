import XCTest
@testable import AJFMCore

final class MovieTests: XCTestCase {

    override func tearDown() {
        // Язык — общее состояние: остальные тесты ждут русский.
        Loc.language = .russian
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    // MARK: - Поиск

    func testSearchURLAsksForUSMovies() throws {
        let url = try XCTUnwrap(AppleMovies.searchURL("  The Matrix "))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "itunes.apple.com")
        XCTAssertEqual(query["term"], "The Matrix")
        XCTAssertEqual(query["media"], "movie")
        XCTAssertEqual(query["entity"], "movie")
        XCTAssertEqual(query["country"], "US")
    }

    func testEmptySearchHasNoURL() {
        XCTAssertNil(AppleMovies.searchURL("   "))
    }

    func testSearchLimitIsClamped() throws {
        let url = try XCTUnwrap(AppleMovies.searchURL("x", limit: 500))
        XCTAssertTrue(url.absoluteString.contains("limit=50"))
    }

    // MARK: - Разбор

    func testParsesMovies() throws {
        let movies = try AppleMovies.parseSearch(json("""
        {"resultCount":1,"results":[{"wrapperType":"track","kind":"feature-movie","trackId":400763833,
         "trackName":"Inception","releaseDate":"2010-07-16T07:00:00Z","longDescription":"Dreams.",
         "artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/100x100bb.jpg"}]}
        """))
        XCTAssertEqual(movies, [Movie(
            id: 400763833, title: "Inception", year: 2010, summary: "Dreams.",
            posterURL: "https://is1-ssl.mzstatic.com/image/thumb/a/600x600bb.jpg")])
    }

    func testSkipsNonMoviesAndDuplicates() throws {
        let movies = try AppleMovies.parseSearch(json("""
        {"results":[
          {"kind":"song","trackId":1,"trackName":"Song"},
          {"kind":"feature-movie","trackId":2,"trackName":"Heat"},
          {"kind":"feature-movie","trackId":2,"trackName":"Heat"},
          {"kind":"feature-movie","trackName":"No id"},
          {"kind":"feature-movie","trackId":3,"trackName":"  "}
        ]}
        """))
        XCTAssertEqual(movies.map(\.id), [2])
    }

    func testMissingFieldsStillGiveAMovie() throws {
        let movies = try AppleMovies.parseSearch(json(#"{"results":[{"kind":"feature-movie","trackId":5,"trackName":"Heat"}]}"#))
        XCTAssertEqual(movies, [Movie(id: 5, title: "Heat")])
    }

    func testShortDescriptionIsAFallback() throws {
        let movies = try AppleMovies.parseSearch(json(
            #"{"results":[{"kind":"feature-movie","trackId":5,"trackName":"Heat","shortDescription":"Cops."}]}"#))
        XCTAssertEqual(movies.first?.summary, "Cops.")
    }

    func testEmptyResponseIsEmpty() throws {
        XCTAssertEqual(try AppleMovies.parseSearch(json(#"{"resultCount":0,"results":[]}"#)), [])
        XCTAssertEqual(try AppleMovies.parseSearch(json("{}")), [])
    }

    func testBrokenJSONIsAnError() {
        XCTAssertThrowsError(try AppleMovies.parseSearch(json("<html>")))
    }

    func testImplausibleYearIsDropped() {
        XCTAssertNil(AppleMovies.year(from: "0001-01-01"))
        XCTAssertNil(AppleMovies.year(from: "abc"))
        XCTAssertNil(AppleMovies.year(from: nil))
        XCTAssertEqual(AppleMovies.year(from: "1995-12-15"), 1995)
    }

    func testPosterMustBeHTTPS() {
        XCTAssertNil(AppleMovies.poster(from: "http://x/100x100bb.jpg"))
        XCTAssertEqual(AppleMovies.poster(from: "https://x/a.jpg"), "https://x/a.jpg")
    }

    // MARK: - Набор

    func testLabelHasYearWhenKnown() {
        XCTAssertEqual(Movie(id: 1, title: "Heat", year: 1995).label, "Heat (1995)")
        XCTAssertEqual(Movie(id: 1, title: "Heat").label, "Heat")
    }

    func testDecorateFilesTheDeckUnderMovies() {
        Loc.language = .russian
        let file = DeckFile(deck: DeckMeta(name: "whatever", folder: "Claude"), notes: [])
        let movie = Movie(id: 1, title: "Heat", year: 1995, posterURL: "https://x/p.jpg")
        let decorated = movie.decorate(file)
        XCTAssertEqual(decorated.deck.folder, "Фильмы")
        XCTAssertEqual(decorated.deck.name, "Heat (1995)")
        XCTAssertEqual(decorated.deck.source, "Heat (1995)")
        XCTAssertEqual(decorated.deck.cover, "https://x/p.jpg")
    }

    func testFolderMatchesTheServerInEveryLanguage() {
        // Те же строки, что FOLDER.movies в backend/src/prompts.ts.
        Loc.language = .russian
        XCTAssertEqual(Movie.folder, "Фильмы")
        Loc.language = .portuguese
        XCTAssertEqual(Movie.folder, "Filmes")
        Loc.language = .english
        XCTAssertEqual(Movie.folder, "Movies")
    }

    func testDeckTopicNamesTheMovie() {
        XCTAssertEqual(Movie(id: 1, title: "Heat", year: 1995).deckTopic, "the movie Heat (1995)")
    }
}
