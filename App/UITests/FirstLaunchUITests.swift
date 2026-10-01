import XCTest

/// Главный путь нового человека: запуск → знакомство → стартовый набор →
/// первое занятие. `-ui-onboarding` показывает знакомство, как на первой
/// установке; остальное — чистая база в памяти.
final class FirstLaunchUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testOnboardingLeadsToTheFirstStudySession() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-onboarding",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 20), "знакомство не открылось")

        // Шагов немного, но их число зависит от того, что уже настроено,
        // поэтому идём «Дальше», пока знакомство не закончится, — с запасом.
        var steps = 0
        var addedStarter = false
        while next.exists && steps < 15 {
            let starter = app.buttons["onboarding.starter"]
            if !addedStarter, starter.exists {
                // На маленьком экране кнопка ниже края — докрутить до неё.
                var swipes = 4
                while !starter.isHittable && swipes > 0 {
                    app.swipeUp()
                    swipes -= 1
                }
                starter.tap()
                addedStarter = true
            }
            next.tap()
            steps += 1
            // Шаг въезжает сбоку: следующее нажатие — по новой кнопке.
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertFalse(next.exists, "знакомство не закончилось за \(steps) шагов")
        XCTAssertTrue(addedStarter, "в знакомстве на пустой базе не было шага со стартовым набором")

        let study = app.buttons["today.study"]
        XCTAssertTrue(study.waitForExistence(timeout: 15),
                      "после знакомства со стартовым набором нечего учить")
        study.tap()
        XCTAssertTrue(app.descendants(matching: .any)["session.progress"].firstMatch
                        .waitForExistence(timeout: 15), "первое занятие не открылось")
    }
}
