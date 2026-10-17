import XCTest
@testable import AJFMCore

final class SupportTicketTests: XCTestCase {

    func testMessageIsTrimmedAndLimited() {
        let long = String(repeating: "😀", count: 3_000)
        let body = BackendAPI.SupportTicketBody(category: .idea, message: "  \(long)  ", contact: nil,
                                                diagnostics: nil)
        XCTAssertEqual(body.message.utf16.count, BackendAPI.SupportTicketBody.messageLimit)
    }

    func testBlankContactIsDropped() {
        let body = BackendAPI.SupportTicketBody(category: .bug, message: "x", contact: "  ", diagnostics: [:])
        XCTAssertNil(body.contact)
        XCTAssertNil(body.diagnostics, "пустая диагностика не отправляется")
        XCTAssertTrue(body.isValid)
    }

    func testBrokenEmailOrEmptyMessageIsInvalid() {
        XCTAssertFalse(BackendAPI.SupportTicketBody(category: .bug, message: "x", contact: "anna",
                                                    diagnostics: nil).isValid)
        XCTAssertFalse(BackendAPI.SupportTicketBody(category: .bug, message: " \n", contact: nil,
                                                    diagnostics: nil).isValid)
    }

    /// Ключи — только буквы: сервер другие не примет.
    func testDiagnosticsKeysAreWhatTheServerAccepts() {
        let diagnostics = SupportDiagnostics.make(appVersion: "1.0 (3)", systemVersion: "26.0", device: "iPhone",
                                                  language: .english, studyLanguage: .italian, cards: 120)
        XCTAssertEqual(diagnostics["cards"], "120")
        XCTAssertEqual(diagnostics["studyLanguage"], "it")
        for key in diagnostics.keys {
            XCTAssertNotNil(key.range(of: "^[a-zA-Z]{1,32}$", options: .regularExpression), key)
        }
    }

    func testTicketDecodesAnsweredStateAndUnknownCategory() throws {
        let json = #"{"id":"R-ABCDEF","category":"weird","message":"m","status":"answered","reply":"Готово","createdAt":1800000000}"#
        let ticket = try JSONDecoder().decode(BackendAPI.SupportTicket.self, from: Data(json.utf8))
        XCTAssertTrue(ticket.isAnswered)
        XCTAssertEqual(ticket.kind, .question, "незнакомая категория — вопрос")
        XCTAssertEqual(ticket.updatedAt, ticket.createdAt)
    }

    func testEveryCategoryHasTitleAndSymbol() {
        for category in SupportCategory.allCases {
            XCTAssertFalse(category.title.isEmpty)
            XCTAssertFalse(category.symbol.isEmpty)
        }
    }
}
