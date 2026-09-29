import XCTest

/// Скриншоты главных экранов на трёх языках и проверка, что тексты не
/// наезжают друг на друга («11карточек»). Гоняется на разных iPhone в
/// отдельном прогоне (`.github/workflows/devices.yml`); скриншоты
/// складываются в артефакт, чтобы глазами проверить переносы и обрезки.
final class ScreenshotUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testRussianScreens() { walkThrough(language: "ru") }
    func testPortugueseScreens() { walkThrough(language: "pt-PT") }
    func testEnglishScreens() { walkThrough(language: "en") }

    // MARK: - Проход

    private func walkThrough(language: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-demo", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : language.replacingOccurrences(of: "-", with: "_")]
        app.launch()
        let prefix = language.prefix(2)

        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 20))
        snap(app, "\(prefix)-1-today")

        let study = app.buttons["today.study"]
        if study.waitForExistence(timeout: 10) {
            study.tap()
            if app.descendants(matching: .any)["session.progress"].firstMatch.waitForExistence(timeout: 10) {
                snap(app, "\(prefix)-2-card")
                let choice = app.buttons["choice"].firstMatch
                if choice.waitForExistence(timeout: 3) {
                    choice.tap()
                    _ = app.buttons["grade.good"].waitForExistence(timeout: 5)
                    snap(app, "\(prefix)-3-answer")
                }
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        for (index, tab) in ["decks", "shows", "rewards", "settings"].enumerated() {
            let button = app.buttons["tab.\(tab)"]
            guard button.waitForExistence(timeout: 10) else { continue }
            button.tap()
            snap(app, "\(prefix)-\(index + 4)-\(tab)")
        }

        let profile = app.buttons["settings.profile"]
        if profile.waitForExistence(timeout: 10) {
            profile.tap()
            snap(app, "\(prefix)-8-profile")
            let help = app.buttons["profile.help"]
            scrollTo(help, in: app)
            if help.exists {
                help.tap()
                snap(app, "\(prefix)-9-help")
            }
        }
    }

    private func scrollTo(_ target: XCUIElement, in app: XCUIApplication) {
        var attempts = 8
        while !(target.exists && target.isHittable) && attempts > 0 {
            app.swipeUp()
            attempts -= 1
        }
    }

    // MARK: - Снимок и проверка

    private func snap(_ app: XCUIApplication, _ name: String) {
        // Анимации появления успевают закончиться.
        Thread.sleep(forTimeInterval: 0.8)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        assertNoOverlappingTexts(app, screen: name)
    }

    /// Два видимых текста не должны заметно перекрываться. Тексты под
    /// стеклянной панелью вкладок и навигацией не считаются: они
    /// прокручиваются под стеклом нарочно.
    private func assertNoOverlappingTexts(_ app: XCUIApplication, screen: String) {
        let window = app.windows.firstMatch.frame
        let tabBarTop = app.buttons["tab.today"].exists ? app.buttons["tab.today"].frame.minY - 8 : window.maxY
        let navBottom = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : window.minY

        let frames = app.staticTexts.allElementsBoundByIndex
            .filter { $0.exists }
            .map { ($0.label, $0.frame) }
            .filter { _, frame in
                frame.height >= 8 && frame.width >= 8
                    && frame.minY >= navBottom && frame.maxY <= tabBarTop
                    && window.contains(frame)
            }

        for i in frames.indices {
            for j in frames.indices where j > i {
                let (labelA, a) = frames[i]
                let (labelB, b) = frames[j]
                // Контейнер и его части: «Мончик, Карточки ждут…» целиком и
                // «Карточки ждут…» внутри, «Новые: 5» и «5». Это один и тот же
                // текст, а не наложение.
                if labelA.contains(labelB) || labelB.contains(labelA)
                    || a.contains(b) || b.contains(a) {
                    continue
                }
                let overlap = a.intersection(b)
                guard !overlap.isNull else { continue }
                let smaller = min(a.width * a.height, b.width * b.height)
                let share = overlap.width * overlap.height / max(smaller, 1)
                XCTAssertLessThan(share, 0.3,
                                  "\(screen): «\(labelA)» наезжает на «\(labelB)» (\(Int(share * 100))%)")
            }
        }
    }
}
