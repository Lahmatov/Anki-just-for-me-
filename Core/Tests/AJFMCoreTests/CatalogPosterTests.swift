import XCTest
@testable import AJFMCore

final class CatalogPosterTests: XCTestCase {

    private func show(_ id: Int, _ name: String, year: Int?, poster: Bool = true) -> TVMaze.Show {
        TVMaze.Show(id: id, name: name,
                    posterURL: poster ? "https://static.tvmaze.com/\(id).jpg" : nil,
                    premieredYear: year)
    }

    func testPicksTheShowWithTheSameNameAndYear() {
        let results = [show(1, "Friends", year: 1994)]
        XCTAssertEqual(CatalogPoster.pick(results, name: "Friends", year: 1994)?.id, 1)
    }

    func testRemakeFromAnotherYearIsSkipped() {
        // Поиск «The Office» первым отдаёт британский оригинал.
        let results = [show(1, "The Office", year: 2001), show(2, "The Office", year: 2005)]
        XCTAssertEqual(CatalogPoster.pick(results, name: "The Office", year: 2005)?.id, 2)
    }

    func testYearMayDifferByOne() {
        let results = [show(1, "Ted Lasso", year: 2019)]
        XCTAssertEqual(CatalogPoster.pick(results, name: "Ted Lasso", year: 2020)?.id, 1)
    }

    func testYearTwoApartIsAnotherShow() {
        let results = [show(1, "House", year: 2002)]
        XCTAssertNil(CatalogPoster.pick(results, name: "House", year: 2004))
    }

    func testSimilarNameIsNotTheSameShow() {
        let results = [show(1, "Lost Girl", year: 2010), show(2, "Lost", year: 2004)]
        XCTAssertEqual(CatalogPoster.pick(results, name: "Lost", year: 2004)?.id, 2)
    }

    func testPunctuationAndCaseDoNotMatter() {
        let results = [show(1, "Greys Anatomy", year: 2005)]
        XCTAssertEqual(CatalogPoster.pick(results, name: "Grey's anatomy", year: 2005)?.id, 1)
    }

    func testWithoutYearNameDecides() {
        let results = [show(1, "Community", year: nil)]
        XCTAssertEqual(CatalogPoster.pick(results, name: "Community", year: 2009)?.id, 1)
        XCTAssertEqual(CatalogPoster.pick(results, name: "Community", year: nil)?.id, 1)
    }

    func testShowWithoutPosterIsUseless() {
        let results = [show(1, "Suits", year: 2011, poster: false), show(2, "Suits", year: 2011)]
        XCTAssertEqual(CatalogPoster.pick(results, name: "Suits", year: 2011)?.id, 2)
    }

    func testNoResultsNoPoster() {
        XCTAssertNil(CatalogPoster.pick([], name: "Friends", year: 1994))
    }

    func testEmptyNameMatchesNothing() {
        XCTAssertNil(CatalogPoster.pick([show(1, "!!!", year: nil)], name: "  ", year: nil))
    }

    /// Весь путь: ответ поиска TVMaze → выбранный постер по https.
    func testFromRealSearchResponse() throws {
        let json = """
        [{"score":0.9,"show":{"id":526,"name":"The Office","premiered":"2001-07-09",
          "image":{"medium":"http://static.tvmaze.com/uk.jpg"}}},
         {"score":0.8,"show":{"id":527,"name":"The Office","premiered":"2005-03-24",
          "image":{"medium":"http://static.tvmaze.com/us.jpg"}}},
         {"score":0.1,"broken":true}]
        """
        let picked = CatalogPoster.pick(TVMaze.parseSearch(Data(json.utf8)), name: "The Office", year: 2005)
        XCTAssertEqual(picked?.id, 527)
        XCTAssertEqual(picked?.posterURL, "https://static.tvmaze.com/us.jpg")
    }
}
