import XCTest
@testable import AJFMCore

final class LessonScanTests: XCTestCase {

    func testPageNumbersAndEmptyLinesGo() {
        let text = LessonScan.clean(lines: ["Aula 5", "", "", "comer — есть", "12", "  ", "beber — пить"])
        XCTAssertEqual(text, "Aula 5\n\ncomer — есть\n\nbeber — пить")
    }

    /// Перенос склеивается, дефис остаётся: составное слово важнее.
    func testWordBrokenAcrossLinesIsJoinedKeepingTheHyphen() {
        XCTAssertEqual(LessonScan.clean(lines: ["o pequeno-", "almoço"]), "o pequeno-almoço")
        XCTAssertEqual(LessonScan.clean(lines: ["Lista -", "Comida"]), "Lista -\nComida",
                       "дефис после пробела и заглавная — не перенос")
    }

    func testRunningHeadersRepeatedOnEveryPageAreDropped() {
        let pages = [
            ["Português A2 — Unidade 3", "comer", "beber", "p. 14"],
            ["Português A2 — Unidade 3", "dormir", "acordar", "p. 15"],
        ]
        XCTAssertEqual(LessonScan.clean(pages: pages), "comer\nbeber\n\ndormir\nacordar")
    }

    func testAWordInTheMiddleOfEveryPageStays() {
        let pages = [["Aula 1", "comer", "x", "y", "fim 1"], ["Aula 2", "z", "comer", "w", "fim 2"]]
        XCTAssertTrue(LessonScan.clean(pages: pages).contains("comer"))
    }

    func testEmptyInput() {
        XCTAssertEqual(LessonScan.clean(pages: []), "")
        XCTAssertEqual(LessonScan.clean(lines: ["", " ", "7"]), "")
    }

    func testLongScanIsCutToTheLessonLimit() {
        let line = String(repeating: "a", count: 1_000)
        let text = LessonScan.clean(lines: Array(repeating: line, count: 40))
        XCTAssertLessThanOrEqual(text.utf16.count, DeckRequest.lessonLimit)
    }
}
