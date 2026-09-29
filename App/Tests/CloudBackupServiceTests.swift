import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

/// Сеть здесь не проверяется — только то, что работает без неё: упаковка
/// снимка и выключатель. Сервер покрыт тестами backend/test/backup.test.ts.
@MainActor
final class CloudBackupServiceTests: XCTestCase {

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.deviceID)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lastCloudBackupDate)
        UserDefaults.standard.removeObject(forKey: SettingsKey.cloudBackupEnabled)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.cloudBackupEnabled)
    }

    private func sampleBackup() throws -> BackupFile {
        let context = try TestDB.makeContext()
        let importer = ImportService(context: context)
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            name: "S01E01", folder: "Сериалы/Friends",
            notes: (1...40).map { NoteData(term: "word \($0)", translation: "слово \($0)") })))
        return try ExportService(context: context).makeBackup()
    }

    func testDeviceLabelIsStableBetweenCalls() {
        let first = CloudBackupService.deviceLabel
        XCTAssertEqual(CloudBackupService.deviceLabel, first,
                       "иначе снимки одного телефона выглядели бы как с разных")
        XCTAssertTrue(first.hasPrefix("iPhone"))
    }

    func testBackupIsOffUntilTurnedOn() {
        XCTAssertFalse(CloudBackupService.isEnabled, "отправлять данные на сервер без спроса нельзя")
        XCTAssertFalse(CloudBackupService.isConfigured)
    }

    func testUploadIfNeededDoesNothingWhenOff() async throws {
        await CloudBackupService(context: try TestDB.makeContext()).uploadIfNeeded()
        XCTAssertNil(CloudBackupService.lastUpload, "выключенный бэкап не ставит отметку")
    }

    func testPackedSnapshotUnpacksToTheSameBackup() async throws {
        let backup = try sampleBackup()
        let packed = try await CloudBackupService.pack(backup)
        let restored = try BackupCoder.decode(try CloudBackupService.unpack(packed.payload))
        XCTAssertEqual(restored.noteCount, backup.noteCount)
        XCTAssertEqual(restored.decks.flatMap { $0.notes.map(\.data.term) },
                       backup.decks.flatMap { $0.notes.map(\.data.term) })
    }

    func testPackedSnapshotIsCompressedAndMarked() async throws {
        let packed = try await CloudBackupService.pack(try sampleBackup())
        XCTAssertLessThan(packed.payload.count, packed.raw, "словарь обязан сжиматься")
        guard case .compressed = CloudBackup.unwrap(packed.payload) else {
            return XCTFail("без метки сервер вернул бы байты, которые не отличить от JSON")
        }
    }

    func testPlainJSONFromTheServerIsAcceptedAsIs() throws {
        let json = try BackupCoder.encode(try sampleBackup())
        XCTAssertEqual(try CloudBackupService.unpack(json), json)
    }

    func testDamagedCompressedSnapshotIsAnError() {
        let garbage = CloudBackup.wrap(compressed: Data(repeating: 0xFF, count: 16))
        XCTAssertThrowsError(try CloudBackupService.unpack(garbage))
    }
}
