import XCTest
import AJFMCore
@testable import AJFM

/// Хранение найденных обложек. Выбор сериала из поиска — в CatalogPosterTests ядра.
@MainActor
final class CatalogPostersTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "CatalogPostersTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private let entry = CatalogIndexEntry(resource: "catalog-show-01", name: "Friends", year: 1994,
                                          rank: 1, episodes: 24, words: 360)

    func testNoPosterBeforeTheFirstSearch() {
        XCTAssertNil(CatalogPosters(defaults: defaults).url(for: entry))
    }

    func testRememberedPosterSurvivesRestart() throws {
        let poster = try XCTUnwrap(URL(string: "https://static.tvmaze.com/friends.jpg"))
        CatalogPosters(defaults: defaults).remember(poster, for: entry.resource)
        XCTAssertEqual(CatalogPosters(defaults: defaults).url(for: entry), poster)
    }

    func testBrokenStoredValueIsIgnored() {
        defaults.set("not a dictionary", forKey: SettingsKey.catalogPosters)
        XCTAssertNil(CatalogPosters(defaults: defaults).url(for: entry))
    }
}
