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

    /// Долистанный до конца экран не прячет последние строки под панелью
    /// вкладок. Жалоба «низ прибит» возвращалась дважды — теперь её ловит тест.
    func testBottomOfEveryTabStaysAboveTabBar() {
        let app = XCUIApplication()
        // С демо-набором экраны длинные, и их есть куда долистывать.
        app.launchArguments = ["-ui-testing", "-ui-demo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        for tab in ["today", "decks", "shows", "rewards", "settings"] {
            let button = app.buttons["tab.\(tab)"]
            XCTAssertTrue(button.waitForExistence(timeout: 15), "нет вкладки \(tab)")
            button.tap()
            for _ in 0..<6 { app.swipeUp(velocity: .fast) }
            // Прокрутка должна успеть остановиться.
            Thread.sleep(forTimeInterval: 1)
            // Верх стеклянной капсулы: кнопка вкладки внутри неё с полями 5 pt.
            let barTop = button.frame.minY - 5
            for text in app.staticTexts.allElementsBoundByIndex where text.exists {
                let frame = text.frame
                guard frame.height > 0, frame.minY < barTop, !button.frame.intersects(frame) else { continue }
                XCTAssertLessThanOrEqual(frame.maxY, barTop + 1,
                                         "\(tab): «\(text.label)» уходит под панель вкладок")
            }
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
        XCTAssertFalse(app.buttons["tab.today"].exists,
                       "в сессии панель вкладок отъедает место у карточки")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 10),
                      "после сессии панель вкладок не вернулась")
    }

    func testTermsOpenFromProfile() {
        let app = launch()
        app.buttons["tab.settings"].tap()

        let profile = app.buttons["settings.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15))
        profile.tap()

        let terms = app.buttons["docs.terms"]
        scrollTo(terms, in: app)
        XCTAssertTrue(terms.waitForExistence(timeout: 15))
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
            // Список ленивый: строки ниже экрана нет в иерархии, пока до
            // неё не прокрутили, — поэтому сначала прокрутка, потом проверка.
            scrollTo(row, in: app)
            XCTAssertTrue(row.waitForExistence(timeout: 15), identifier)
            row.tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 15), title)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }
}
