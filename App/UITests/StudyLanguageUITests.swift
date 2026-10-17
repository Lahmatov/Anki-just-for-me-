import XCTest

/// Переключение изучаемого языка (P-67): у каждого языка своя база, и при
/// возвращении всё на месте.
final class StudyLanguageUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func choose(_ name: String, in app: XCUIApplication) {
        let menu = app.buttons["studyLanguage.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "нет переключателя языка на «Сегодня»")
        menu.tap()
        let item = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "в меню нет языка \(name)")
        item.tap()
    }

    func testSwitchingLanguagesKeepsEachLanguagesDecks() {
        let app = XCUIApplication()
        // -ui-demo: в английской базе уже есть стартовый набор.
        app.launchArguments = ["-ui-testing", "-ui-demo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["today.study"].waitForExistence(timeout: 20), "в английской базе нечего учить")

        choose("Português", in: app)
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["today.study"].waitForExistence(timeout: 5),
                       "английские карточки попали в португальскую базу")

        choose("English", in: app)
        XCTAssertTrue(app.buttons["today.study"].waitForExistence(timeout: 15),
                      "после возвращения английские наборы пропали")
    }
}
