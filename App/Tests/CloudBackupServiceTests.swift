import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

/// Сеть здесь не проверяется — только то, что работает без неё.
/// Протокол Neon и запросы покрыты тестами ядра.
@MainActor
final class CloudBackupServiceTests: XCTestCase {

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.deviceID)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lastCloudBackupDate)
    }

    func testDeviceLabelIsStableBetweenCalls() {
        let first = CloudBackupService.deviceLabel
        XCTAssertEqual(CloudBackupService.deviceLabel, first,
                       "иначе снимки одного телефона выглядели бы как с разных")
        XCTAssertTrue(first.hasPrefix("iPhone"))
    }

    func testUploadIfNeededDoesNothingWithoutConnection() async throws {
        let saved = Keychain.get(Keychain.neonConnection)
        Keychain.set("", for: Keychain.neonConnection)
        defer { Keychain.set(saved ?? "", for: Keychain.neonConnection) }

        await CloudBackupService(context: try TestDB.makeContext()).uploadIfNeeded()
        XCTAssertNil(CloudBackupService.lastUpload, "без подключения отметка не ставится")
        XCTAssertFalse(CloudBackupService.isConfigured)
    }

    func testBrokenConnectionStringCountsAsNotConfigured() {
        let saved = Keychain.get(Keychain.neonConnection)
        Keychain.set("hello", for: Keychain.neonConnection)
        defer { Keychain.set(saved ?? "", for: Keychain.neonConnection) }
        XCTAssertFalse(CloudBackupService.isConfigured)
    }
}
