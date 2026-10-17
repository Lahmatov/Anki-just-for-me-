import XCTest
@testable import AJFMCore

final class NetworkProblemTests: XCTestCase {
    func testAirplaneModeIsOffline() {
        XCTAssertEqual(NetworkProblem(urlErrorCode: -1009), .offline)
        XCTAssertEqual(NetworkProblem(urlErrorCode: -1020), .offline)
    }

    func testTimeoutIsSlow() {
        XCTAssertEqual(NetworkProblem(urlErrorCode: -1001), .slow)
    }

    func testSwitchingNetworksIsDropped() {
        XCTAssertEqual(NetworkProblem(urlErrorCode: -1005), .dropped)
        XCTAssertEqual(NetworkProblem(urlErrorCode: -1004), .dropped)
    }

    func testUnknownCodeIsOther() {
        XCTAssertEqual(NetworkProblem(urlErrorCode: -1202), .other, "сертификат — не сеть, повтор не поможет")
        XCTAssertEqual(NetworkProblem(urlErrorCode: 0), .other)
    }
}

final class NetworkRetryPolicyTests: XCTestCase {
    func testDroppedIdempotentRequestIsRetriedOnce() {
        XCTAssertNotNil(NetworkRetryPolicy.delay(for: .dropped, attempt: 0, idempotent: true))
        XCTAssertNil(NetworkRetryPolicy.delay(for: .dropped, attempt: 1, idempotent: true))
    }

    func testSlowIdempotentRequestIsRetriedOnce() {
        XCTAssertEqual(NetworkRetryPolicy.delay(for: .slow, attempt: 0, idempotent: true), .seconds(1))
    }

    func testNonIdempotentRequestIsNeverRetried() {
        // Разговор с Мончиком списывает лимит — второй запрос стоил бы дважды.
        XCTAssertNil(NetworkRetryPolicy.delay(for: .dropped, attempt: 0, idempotent: false))
        XCTAssertNil(NetworkRetryPolicy.delay(for: .slow, attempt: 0, idempotent: false))
    }

    func testOfflineFailsFast() {
        XCTAssertNil(NetworkRetryPolicy.delay(for: .offline, attempt: 0, idempotent: true))
    }

    func testOtherErrorsAreNotRetried() {
        XCTAssertNil(NetworkRetryPolicy.delay(for: .other, attempt: 0, idempotent: true))
    }
}

final class TransportFailureTests: XCTestCase {
    func testOfflineAndSlowGetTheirOwnMessage() {
        XCTAssertEqual(BackendAPI.Failure.transport(urlErrorCode: -1009), .offline)
        XCTAssertEqual(BackendAPI.Failure.transport(urlErrorCode: -1001), .slow)
        XCTAssertEqual(BackendAPI.Failure.transport(urlErrorCode: -1005), .network)
        XCTAssertNotEqual(BackendAPI.Failure.offline.errorDescription, BackendAPI.Failure.slow.errorDescription)
    }

    func testTransportFailuresCountAsInterruptionAfterBackground() {
        // Набор, оборванный в фоне, продолжается и на пути через сервер.
        for failure in [BackendAPI.Failure.network, .offline, .slow] {
            XCTAssertTrue(failure.isTransport)
            XCTAssertTrue(NetworkInterruption.shouldResume(after: failure, wasBackgrounded: true))
        }
    }

    func testServerAnswerIsNotTransport() {
        let failure = BackendAPI.Failure.server(code: "quota_exceeded", status: 402)
        XCTAssertFalse(failure.isTransport)
        XCTAssertFalse(NetworkInterruption.shouldResume(after: failure, wasBackgrounded: true))
    }
}
