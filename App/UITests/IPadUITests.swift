import XCTest
import UIKit

/// iPad (P-70): приложение открывается в обеих ориентациях, вкладки на
/// месте, а колонка не растягивается на весь экран. На iPhone тесты пропускаются.
final class IPadUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func launch() throws -> XCUIApplication {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "только для iPad")
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-demo", "-ui-demo-lesson",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 20), "приложение не открылось")
        return app
    }

    func testEveryTabOpensInLandscape() throws {
        let app = try launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        for tab in ["tab.decks", "tab.shows", "tab.settings", "tab.today"] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "в альбомной ориентации нет вкладки \(tab)")
            button.tap()
        }
        XCTAssertTrue(app.buttons["today.study"].waitForExistence(timeout: 10))
    }

    /// Карточки — колонкой по центру, а не во всю ширину планшета.
    func testContentIsAReadableColumn() throws {
        let app = try launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let card = app.buttons["today.lessons"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(card.frame.width, 760, "карточка растянулась на \(card.frame.width) pt")
        XCTAssertEqual(card.frame.midX, window.midX, accuracy: 40, "колонка не по центру")
    }

    func testLessonTrainersWorkOnIPad() throws {
        let app = try launch()
        let lessons = app.buttons["today.lessons"]
        XCTAssertTrue(lessons.waitForExistence(timeout: 15))
        lessons.tap()
        let step = app.descendants(matching: .any)["lessons.step.0"].firstMatch
        XCTAssertTrue(step.waitForExistence(timeout: 15))
        step.tap()
        XCTAssertTrue(app.descendants(matching: .any)["lesson.quiz"].firstMatch.waitForExistence(timeout: 15))
    }
}
