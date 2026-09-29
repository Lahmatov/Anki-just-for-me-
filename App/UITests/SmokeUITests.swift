import XCTest

/// Дымовые UI-тесты: приложение запускается на симуляторе и проходит главный
/// путь — вкладки, стартовый набор, сессия, документы. Логику проверяют
/// тесты ядра и базы; здесь ловится то, что они не видят: экран не
/// открывается, кнопка не нажимается, навигация ведёт не туда.
///
/// Элементы ищутся по идентификаторам (`accessibilityIdentifier`), а не по
/// тексту: тексты на трёх языках, а идентификаторы — одни.
final class SmokeUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Чистая база в памяти, без заставки и знакомства; английский —
        // чтобы проверять заголовки документов одной строкой.
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Прокрутить список, пока элемент не окажется под пальцем.
    private func scrollTo(_ target: XCUIElement, in app: XCUIApplication, attempts: Int = 8) {
        var left = attempts
        while !(target.exists && target.isHittable) && left > 0 {
            app.swipeUp()
            left -= 1
        }
    }

    func testEveryTabOpens() {
        let app = launch()
        for tab in ["today", "decks", "shows", "rewards", "settings", "today"] {
            let button = app.buttons["tab.\(tab)"]
            XCTAssertTrue(button.waitForExistence(timeout: 15), "нет вкладки \(tab)")
            button.tap()
        }
    }

    func testStarterDeckLeadsToAStudySession() {
        let app = launch()
        let starter = app.buttons["today.starter"]
        XCTAssertTrue(starter.waitForExistence(timeout: 15), "на пустой базе нет стартового набора")
        starter.tap()

        let study = app.buttons["today.study"]
        XCTAssertTrue(study.waitForExistence(timeout: 15), "после стартового набора нечего учить")
        study.tap()

        XCTAssertTrue(element(app, "session.progress").waitForExistence(timeout: 15),
                      "сессия не открылась")
    }

    func testTermsOpenFromProfile() {
        let app = launch()
        app.buttons["tab.settings"].tap()

        let profile = app.buttons["settings.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15))
        profile.tap()

        let terms = app.buttons["docs.terms"]
        XCTAssertTrue(terms.waitForExistence(timeout: 15))
        scrollTo(terms, in: app)
        terms.tap()

        XCTAssertTrue(app.staticTexts["Recap — Terms of Use"].waitForExistence(timeout: 15),
                      "условия не открылись или не нашлись в сборке")
    }

    func testPrivacyAndLicensesOpenFromProfile() {
        let app = launch()
        app.buttons["tab.settings"].tap()
        app.buttons["settings.profile"].tap()

        for (identifier, title) in [("docs.privacy", "Recap — Privacy Policy"),
                                    ("docs.licenses", "Recap — Licenses")] {
            let row = app.buttons[identifier]
            XCTAssertTrue(row.waitForExistence(timeout: 15), identifier)
            scrollTo(row, in: app)
            row.tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 15), title)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }
}
