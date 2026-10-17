import XCTest

/// Тема: светлая, тёмная или как в системе — выбор в настройках держится,
/// а сохранённая тёмная применяется с запуска.
final class AppearanceUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extra + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 20), "приложение не открылось")
        return app
    }

    private func themePicker(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["tab.settings"].tap()
        let picker = app.segmentedControls["settings.theme"]
        // Медленно и в обе стороны: с крупным шрифтом быстрый свайп проскакивал
        // строку, а форма убирает проскоченные строки из дерева.
        for _ in 0..<12 where !(picker.exists && picker.isHittable) { app.swipeUp(velocity: .slow) }
        for _ in 0..<12 where !(picker.exists && picker.isHittable) { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "в настройках нет выбора темы")
        return picker
    }

    func testSystemThemeIsTheDefault() {
        let app = launch()
        XCTAssertTrue(themePicker(app).buttons["Auto"].isSelected)
    }

    func testChosenThemeStaysAfterLeavingSettings() {
        let app = launch()
        for name in ["Dark", "Light", "Auto"] {
            themePicker(app).buttons[name].tap()
            app.buttons["tab.today"].tap()
            XCTAssertTrue(themePicker(app).buttons[name].isSelected, "тема «\(name)» не сохранилась")
        }
    }

    /// Сохранённая тема (здесь — аргументом запуска) видна с первого экрана.
    func testSavedDarkThemeIsUsedFromLaunch() {
        let app = launch(["-appearance", "dark"])
        XCTAssertTrue(themePicker(app).buttons["Dark"].isSelected)
    }
}
