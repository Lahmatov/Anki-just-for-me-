import XCTest
@testable import AJFMCore

final class NetworkInterruptionTests: XCTestCase {

    func testLostConnectionIsInterruption() {
        XCTAssertTrue(NetworkInterruption.isInterruption(URLError(.networkConnectionLost)))
    }

    func testCancellationIsInterruption() {
        XCTAssertTrue(NetworkInterruption.isInterruption(CancellationError()))
        XCTAssertTrue(NetworkInterruption.isInterruption(URLError(.cancelled)))
    }

    func testNSErrorFromURLSessionIsRecognised() {
        let error = NSError(domain: NSURLErrorDomain, code: URLError.Code.timedOut.rawValue)
        XCTAssertTrue(NetworkInterruption.isInterruption(error))
    }

    func testBadServerResponseIsNotInterruption() {
        XCTAssertFalse(NetworkInterruption.isInterruption(URLError(.badServerResponse)))
    }

    func testOrdinaryErrorIsNotInterruption() {
        struct Boom: Error {}
        XCTAssertFalse(NetworkInterruption.isInterruption(Boom()))
    }

    func testResumeOnlyAfterBackground() {
        let lost = URLError(.networkConnectionLost)
        XCTAssertTrue(NetworkInterruption.shouldResume(after: lost, wasBackgrounded: true))
        XCTAssertFalse(NetworkInterruption.shouldResume(after: lost, wasBackgrounded: false))
    }

    func testRealFailureIsNotResumedEvenAfterBackground() {
        XCTAssertFalse(NetworkInterruption.shouldResume(
            after: URLError(.userAuthenticationRequired), wasBackgrounded: true))
    }

    func testDeckBodyCarriesRequestId() throws {
        let body = BackendAPI.DeckBody(showId: 1, season: 1, episode: 1, language: .russian, level: nil,
                                       wordCount: 20, knownTerms: [], subtitles: nil, requestId: "req-12345678")
        let json = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        XCTAssertTrue(json.contains("req-12345678"))
    }

    func testDeckBodyWithoutRequestIdOmitsIt() throws {
        let body = BackendAPI.DeckBody(showId: 1, season: 1, episode: 1, language: .russian, level: nil,
                                       wordCount: 20, knownTerms: [], subtitles: nil)
        let json = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        XCTAssertFalse(json.contains("requestId"))
    }
}
