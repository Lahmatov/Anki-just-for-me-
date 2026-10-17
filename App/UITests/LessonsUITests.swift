import XCTest

/// Уроки (P-69) от «Сегодня» до итогов тренажёров и теста. Правила тренажёров,
/// теста и спряжения проверяет ядро; здесь — что путь по экранам проходится
/// целиком и ничего не застревает. Сеть не нужна: `-ui-demo-lesson` кладёт урок.
final class LessonsUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = ["-ui-demo-lesson"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extra + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 20), "приложение не открылось")
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func scrollTo(_ target: XCUIElement, in app: XCUIApplication, attempts: Int = 8) {
        var left = attempts
        while !(target.exists && target.isHittable) && left > 0 {
            app.swipeUp()
            left -= 1
        }
    }

    private func tap(_ identifier: String, in app: XCUIApplication, scrolling: Bool = true) {
        let target = element(app, identifier)
        if scrolling { scrollTo(target, in: app) }
        XCTAssertTrue(target.waitForExistence(timeout: 15), "нет «\(identifier)»")
        target.tap()
    }

    private func openLesson(_ app: XCUIApplication) {
        tap("today.lessons", in: app)
        XCTAssertTrue(element(app, "lessons.step.0").waitForExistence(timeout: 15), "на карте нет урока")
        element(app, "lessons.step.0").tap()
        XCTAssertTrue(element(app, "lesson.review").waitForExistence(timeout: 15), "страница урока не открылась")
    }

    /// Пройти тренажёр до итога любыми ответами.
    private func finishDrill(_ app: XCUIApplication, answerID: String, checkID: String, nextID: String,
                             scoreID: String, answer: String = "x", limit: Int = 15) {
        for _ in 0..<limit {
            if element(app, scoreID).exists { return }
            let field = element(app, answerID)
            XCTAssertTrue(field.waitForExistence(timeout: 10), "нет поля ответа")
            field.tap()
            field.typeText(answer)
            tap(checkID, in: app, scrolling: false)
            tap(nextID, in: app, scrolling: false)
        }
        XCTAssertTrue(element(app, scoreID).waitForExistence(timeout: 10), "тренажёр не дошёл до итога")
    }

    func testEmptyLessonMapOffersToAddALesson() {
        let app = launch([])
        tap("today.lessons", in: app)
        tap("lessons.add", in: app)
        XCTAssertTrue(element(app, "lesson.text").waitForExistence(timeout: 15),
                      "«Добавить урок» не открыл поле для конспекта")
        XCTAssertTrue(element(app, "lesson.photos").exists, "нет кнопки «Из фото»")
        XCTAssertTrue(element(app, "lesson.pdf").exists, "нет кнопки «Из PDF»")
    }

    func testLessonPageHasEveryTrainer() {
        let app = launch()
        openLesson(app)
        for identifier in ["lesson.drill.translation", "lesson.drill.cloze", "lesson.drill.dictation",
                           "lesson.drill.pronunciation", "lesson.conjugation", "lesson.quiz",
                           "lesson.speak", "lesson.chat"] {
            let target = element(app, identifier)
            scrollTo(target, in: app)
            XCTAssertTrue(target.exists, "на странице урока нет «\(identifier)»")
        }
    }

    func testTranslationDrillReachesTheResult() {
        let app = launch()
        openLesson(app)
        tap("lesson.drill.translation", in: app)
        finishDrill(app, answerID: "drill.answer", checkID: "drill.check", nextID: "drill.next",
                    scoreID: "drill.score", answer: "go")
    }

    func testDictationReachesTheResult() {
        let app = launch()
        openLesson(app)
        tap("lesson.drill.dictation", in: app)
        finishDrill(app, answerID: "drill.answer", checkID: "drill.check", nextID: "drill.next",
                    scoreID: "drill.score", answer: "we go")
    }

    func testConjugationReachesTheResult() {
        let app = launch()
        openLesson(app)
        tap("lesson.conjugation", in: app)
        finishDrill(app, answerID: "conjugation.answer", checkID: "conjugation.check",
                    nextID: "conjugation.next", scoreID: "drill.score", answer: "went")
    }

    /// Тест до итога и обратно на карту: результат виден у урока.
    func testQuizScoreShowsOnTheMap() {
        let app = launch()
        openLesson(app)
        tap("lesson.quiz", in: app)
        for _ in 0..<12 {
            if element(app, "quiz.score").exists { break }
            let choice = app.buttons["quiz.choice"].firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 10), "нет вариантов ответа")
            choice.tap()
            tap("quiz.next", in: app, scrolling: false)
        }
        XCTAssertTrue(element(app, "quiz.score").waitForExistence(timeout: 10), "тест не дошёл до итога")

        // Назад — на страницу урока, затем на карту.
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let step = element(app, "lessons.step.0")
        XCTAssertTrue(step.waitForExistence(timeout: 10))
        // До теста у шага «no quiz yet», после — процент.
        XCTAssertTrue(step.label.contains("%"), "на карте не виден результат теста: \(step.label)")
    }
}
