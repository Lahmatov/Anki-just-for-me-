import XCTest
@testable import AJFMCore

final class CloudBackupTests: XCTestCase {

    // MARK: - Расписание

    func testUploadIsDueDaily() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(CloudBackup.isDue(lastUpload: nil, now: now))
        XCTAssertFalse(CloudBackup.isDue(lastUpload: now.addingTimeInterval(-3_600), now: now))
        XCTAssertTrue(CloudBackup.isDue(lastUpload: now.addingTimeInterval(-86_400), now: now))
    }

    func testClockMovedBackDoesNotBlockUploadsForever() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(CloudBackup.isDue(lastUpload: now.addingTimeInterval(86_400 * 30), now: now))
    }

    // MARK: - Упаковка

    func testWrappedPayloadUnwrapsToTheSameBytes() {
        let body = Data([0x78, 0x9C, 0x01, 0x02, 0x03])
        XCTAssertEqual(CloudBackup.unwrap(CloudBackup.wrap(compressed: body)), .compressed(body))
    }

    func testPlainJSONIsNotMistakenForCompressed() {
        let json = Data(#"{"format":"ajfm-backup"}"#.utf8)
        XCTAssertEqual(CloudBackup.unwrap(json), .plain(json))
    }

    func testDataShorterThanTheMarkIsPlain() {
        XCTAssertEqual(CloudBackup.unwrap(Data("RC".utf8)), .plain(Data("RC".utf8)))
        XCTAssertEqual(CloudBackup.unwrap(Data()), .plain(Data()))
    }

    func testMarkAloneIsAnEmptyCompressedBody() {
        XCTAssertEqual(CloudBackup.unwrap(CloudBackup.magic), .compressed(Data()))
    }

    func testUnwrapWorksOnASliceWithNonZeroStartIndex() {
        // Data из середины буфера начинается не с нуля — prefix/dropFirst обязаны это учитывать.
        let buffer = Data([9, 9]) + CloudBackup.wrap(compressed: Data([1, 2]))
        let slice = buffer.dropFirst(2)
        XCTAssertEqual(CloudBackup.unwrap(slice), .compressed(Data([1, 2])))
    }

    // MARK: - Запрос

    func testUploadQueryCarriesTheDescription() {
        let items = CloudBackup.uploadQuery(device: "iPhone · AB12", noteCount: 120, matureWords: 30)
        XCTAssertEqual(items.map(\.name), ["device", "notes", "mature"])
        XCTAssertEqual(items.map(\.value), ["iPhone · AB12", "120", "30"])
    }

    func testUploadQueryClampsWhatTheServerWouldReject() {
        let items = CloudBackup.uploadQuery(device: String(repeating: "x", count: 100),
                                            noteCount: -1, matureWords: -5)
        XCTAssertEqual(items[0].value?.count, 64)
        XCTAssertEqual(items[1].value, "0")
        XCTAssertEqual(items[2].value, "0")
    }

    // MARK: - Список

    func testListDecodesServerResponse() throws {
        let json = Data("""
        {"backups":[{"id":"ab12","createdAt":1800000000,"device":"iPhone · AB12",
          "noteCount":120,"matureWords":30,"size":2048}],"keep":7,"signedIn":true}
        """.utf8)
        let list = try JSONDecoder().decode(CloudBackupList.self, from: json)
        XCTAssertEqual(list.keep, 7)
        XCTAssertTrue(list.signedIn)
        XCTAssertEqual(list.backups, [CloudBackupEntry(
            id: "ab12", device: "iPhone · AB12", createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            noteCount: 120, matureWords: 30, bytes: 2048)])
    }

    func testMissingOptionalFieldsDefaultToZero() throws {
        let json = Data(#"{"id":"x","createdAt":1}"#.utf8)
        let entry = try JSONDecoder().decode(CloudBackupEntry.self, from: json)
        XCTAssertEqual(entry.noteCount, 0)
        XCTAssertEqual(entry.bytes, 0)
        XCTAssertEqual(entry.device, "")
    }

    func testEntryWithoutIdIsRejected() {
        let json = Data(#"{"createdAt":1,"device":"x"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CloudBackupEntry.self, from: json))
    }

    func testEntryWithTextDateIsRejected() {
        let json = Data(#"{"id":"x","createdAt":"yesterday"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CloudBackupEntry.self, from: json))
    }
}
