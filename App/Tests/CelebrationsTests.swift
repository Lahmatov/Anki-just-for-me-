import XCTest
@testable import AJFM

/// Общий показ праздника: экраны просят, корень рисует.
@MainActor
final class CelebrationsTests: XCTestCase {

    override func tearDown() {
        Celebrations.shared.dismiss()
    }

    func testShowSetsTheMoment() {
        Celebrations.shared.show("3 дня подряд!", subtitle: "Мончик гордится")
        XCTAssertEqual(Celebrations.shared.current?.title, "3 дня подряд!")
        XCTAssertEqual(Celebrations.shared.current?.subtitle, "Мончик гордится")
    }

    func testDismissClearsTheMoment() {
        Celebrations.shared.show("Цель дня выполнена!")
        Celebrations.shared.dismiss()
        XCTAssertNil(Celebrations.shared.current)
    }

    /// Тот же заголовок второй раз — новый праздник, а не «ничего не изменилось»:
    /// иначе переход не проиграется и окно не появится.
    func testSameTitleTwiceIsANewMoment() {
        Celebrations.shared.show("Сезон 1 пройден!")
        let first = Celebrations.shared.current
        Celebrations.shared.show("Сезон 1 пройден!")
        XCTAssertNotEqual(Celebrations.shared.current, first)
    }
}
