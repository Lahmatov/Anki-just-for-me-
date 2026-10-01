import XCTest

/// Сериал для учёбы, карта по сериям, каталог и Recap — путь человека по
/// экранам. Правила пути и выбора проверяют тесты ядра и базы; здесь —
/// что кнопки есть, нажимаются и ведут куда надо.
///
/// Сеть не нужна: `-ui-demo-show` кладёт в базу сериал из каталога с двумя
/// сериями и словами первой, а постеры в тестах не ждём — плитка без них
/// остаётся цветной и нажимается так же.
final class JourneyUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extra + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 20), "приложение не открылось")
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Прокрутить, пока элемент не окажется под пальцем.
    private func scrollTo(_ target: XCUIElement, in app: XCUIApplication, attempts: Int = 8) {
        var left = attempts
        while !(target.exists && target.isHittable) && left > 0 {
            app.swipeUp()
            left -= 1
        }
    }

    private func openMap(_ app: XCUIApplication) {
        let card = app.buttons["journey.card"]
        scrollTo(card, in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 15), "на «Сегодня» нет карты")
        card.tap()
    }

    /// Без выбранного сериала карта предлагает выбрать; выбранный из
    /// каталога сразу получает шаги по сериям.
    func testChoosingAShowFromTheMapBuildsTheEpisodePath() {
        let app = launch(["-ui-demo"])
        openMap(app)

        let choose = app.buttons["map.choose"]
        XCTAssertTrue(choose.waitForExistence(timeout: 15), "пустая карта не предлагает выбрать сериал")
        choose.tap()

        let first = app.buttons["studyShow.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 15), "в выборе нет сериалов каталога")
        first.tap()

        XCTAssertTrue(app.buttons["map.change"].waitForExistence(timeout: 15), "после выбора нет шапки сериала")
        XCTAssertTrue(element(app, "map.e1x1").waitForExistence(timeout: 15), "нет шага первой серии")
    }

    /// Шаг серии со словами ведёт прямо в занятие.
    func testEpisodeStepStartsAStudySession() {
        let app = launch(["-ui-demo-show"])
        openMap(app)

        let step = element(app, "map.e1x1")
        XCTAssertTrue(step.waitForExistence(timeout: 15), "нет шага первой серии")
        step.tap()

        let study = app.buttons["step.study"]
        XCTAssertTrue(study.waitForExistence(timeout: 10), "в шаге серии нет кнопки «учить»")
        study.tap()
        XCTAssertTrue(element(app, "session.progress").waitForExistence(timeout: 15), "занятие не открылось")
    }

    /// Серия без слов, но с готовыми словами в каталоге, получает их с карты.
    func testCatalogWordsCanBeAddedFromTheMap() {
        let app = launch(["-ui-demo-show"])
        openMap(app)

        let step = element(app, "map.e1x2")
        XCTAssertTrue(step.waitForExistence(timeout: 15), "нет шага второй серии")
        step.tap()

        let add = app.buttons["step.addWords"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "в шаге серии нет готовых слов")
        add.tap()
        // Слова добавляются, когда шторка уже закрылась.
        XCTAssertTrue(add.waitForNonExistence(timeout: 10), "шторка шага не закрылась")
        step.tap()
        XCTAssertTrue(app.buttons["step.study"].waitForExistence(timeout: 10),
                      "после добавления слов серию нельзя учить")
    }

    /// С карты — в серию, из серии — в Recap: слова, вопросы, пересказ.
    func testRecapOpensFromTheMap() {
        let app = launch(["-ui-demo-show"])
        openMap(app)

        let step = element(app, "map.e1x1")
        XCTAssertTrue(step.waitForExistence(timeout: 15))
        step.tap()
        let openEpisode = app.buttons["step.open"]
        XCTAssertTrue(openEpisode.waitForExistence(timeout: 10), "из шага нельзя открыть серию")
        openEpisode.tap()

        let recap = app.buttons["episode.recap"]
        scrollTo(recap, in: app)
        XCTAssertTrue(recap.waitForExistence(timeout: 15), "в серии нет Recap")
        recap.tap()

        for part in ["recap.words", "recap.questions", "recap.retell"] {
            let item = element(app, part)
            scrollTo(item, in: app)
            XCTAssertTrue(item.waitForExistence(timeout: 10), "в Recap нет шага \(part)")
        }
    }

    /// Плитка готового сериала открывает его серии, и сериал можно сделать
    /// главным — кнопка сменяется отметкой «на карте».
    func testCatalogTileOpensTheShowAndMakesItTheStudyShow() {
        let app = launch([])
        let shows = app.buttons["tab.shows"]
        XCTAssertTrue(shows.waitForExistence(timeout: 15))
        shows.tap()

        // Плитка — ссылка с объединённым для VoiceOver содержимым: её тип в
        // дереве не обязательно «кнопка», поэтому ищем по идентификатору.
        let tile = element(app, "catalog.1")
        scrollTo(tile, in: app)
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "нет плитки готового сериала")
        tile.tap()

        XCTAssertTrue(element(app, "catalog.add.1").waitForExistence(timeout: 15), "у сериала нет серий")
        let study = element(app, "studyThisShow")
        scrollTo(study, in: app)
        XCTAssertTrue(study.waitForExistence(timeout: 10), "нет кнопки «учить этот сериал»")
        study.tap()
        XCTAssertTrue(study.waitForNonExistence(timeout: 10),
                      "после выбора кнопка не сменилась отметкой «на карте»")
    }
}
