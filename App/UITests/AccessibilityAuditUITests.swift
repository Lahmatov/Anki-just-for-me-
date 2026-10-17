import XCTest

/// Автоматический аудит доступности (Apple, WWDC23 «Perform accessibility
/// audits for your app»): на каждом главном экране XCTest сам ищет кнопки
/// без подписи и элементы с неверной ролью — то, что слышит VoiceOver.
/// Аудит видит только экран целиком в текущем состоянии, поэтому — по экранам.
final class AccessibilityAuditUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-demo", "-ui-demo-lesson",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 20), "приложение не открылось")
        return app
    }

    /// Подписи и роли — то, без чего VoiceOver бесполезен. Контраст и размеры
    /// попаданий проверяет отдельный проход по скриншотам и ручной список.
    private func audit(_ app: XCUIApplication, _ screen: String) {
        do {
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait]) { issue in
                // Системное — клавиатура, строка состояния — не наше.
                let owner = issue.element?.identifier ?? ""
                return owner.hasPrefix("UIKeyboard") || owner == "StatusBar"
            }
        } catch {
            XCTFail("\(screen): \(error)")
        }
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func testMainTabs() {
        let app = launch()
        for tab in ["tab.today", "tab.decks", "tab.shows", "tab.settings"] {
            app.buttons[tab].tap()
            XCTAssertTrue(app.buttons[tab].waitForExistence(timeout: 10))
            audit(app, tab)
        }
    }

    func testStudyCard() {
        let app = launch()
        let study = app.buttons["today.study"]
        XCTAssertTrue(study.waitForExistence(timeout: 15))
        study.tap()
        Thread.sleep(forTimeInterval: 1)
        audit(app, "card")
    }

    func testLessonScreens() {
        let app = launch()
        let lessons = element(app, "today.lessons")
        for _ in 0..<12 where !(lessons.exists && lessons.isHittable) { app.swipeUp(velocity: .slow) }
        lessons.tap()
        audit(app, "lessons map")
        let step = element(app, "lessons.step.0")
        XCTAssertTrue(step.waitForExistence(timeout: 15))
        step.tap()
        XCTAssertTrue(element(app, "lesson.review").waitForExistence(timeout: 15))
        audit(app, "lesson page")
    }
}

/// Время запуска — практика из открытых приложений: замер на каждом
/// устройстве матрицы, чтобы рост был виден в журнале прогона, а не в отзывах.
final class LaunchPerformanceUITests: XCTestCase {
    func testLaunchTime() {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-ui-demo"]
            app.launch()
        }
    }
}
