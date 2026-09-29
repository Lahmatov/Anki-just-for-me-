import XCTest
import UIKit
import AJFMCore
@testable import AJFM

/// Профиль живёт только на телефоне, и «Удалить все данные» обязано
/// забирать и его — фото человека особенно.
@MainActor
final class ProfileStoreTests: XCTestCase {

    private var suite = ""
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUp() async throws {
        suite = "profile-test-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory
            .appending(path: "profile-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> ProfileStore {
        ProfileStore(defaults: defaults, directory: directory)
    }

    private func jpeg(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            .jpegData(compressionQuality: 0.9)!
    }

    private var avatarFile: URL { directory.appending(path: "avatar.jpg") }

    // MARK: - Имя

    func testNameIsCleanedAndSurvivesRestart() {
        makeStore().setName("  Ana   Silva ")
        XCTAssertEqual(makeStore().name, "Ana Silva")
    }

    func testEmptyNameIsRemovedFromSettings() {
        let store = makeStore()
        store.setName("Ana")
        store.setName("   ")
        XCTAssertNil(defaults.string(forKey: SettingsKey.profileName))
    }

    func testAppleNameDoesNotOverwriteOwnName() {
        let store = makeStore()
        store.setName("Мончик")
        store.adoptName(givenName: "Ana", familyName: "Silva")
        XCTAssertEqual(store.name, "Мончик")
    }

    func testAppleNameFillsEmptyProfile() {
        let store = makeStore()
        store.adoptName(givenName: "Ana", familyName: "Silva")
        XCTAssertEqual(store.name, "Ana Silva")
        XCTAssertEqual(store.initials, "AS")
    }

    // MARK: - Аватарка

    func testPhotoIsCroppedToSquareAndScaledDown() throws {
        let store = makeStore()
        try store.setPhoto(jpeg(width: 1600, height: 900))
        let saved = try XCTUnwrap(UIImage(data: Data(contentsOf: avatarFile)))
        XCTAssertEqual(saved.size.width * saved.scale, 512)
        XCTAssertEqual(saved.size.height * saved.scale, 512)
        XCTAssertEqual(store.avatar, .photo)
    }

    func testSmallPhotoIsNotScaledUp() throws {
        try makeStore().setPhoto(jpeg(width: 120, height: 200))
        let saved = try XCTUnwrap(UIImage(data: Data(contentsOf: avatarFile)))
        XCTAssertEqual(saved.size.width * saved.scale, 120)
    }

    func testPhotoSurvivesRestart() throws {
        try makeStore().setPhoto(jpeg(width: 300, height: 300))
        let reopened = makeStore()
        XCTAssertEqual(reopened.avatar, .photo)
        XCTAssertNotNil(reopened.photo)
    }

    func testGarbageIsNotAcceptedAsPhoto() {
        let store = makeStore()
        XCTAssertThrowsError(try store.setPhoto(Data("not an image".utf8)))
        XCTAssertEqual(store.avatar, .initials)
        XCTAssertFalse(FileManager.default.fileExists(atPath: avatarFile.path))
    }

    func testRemovingPhotoDeletesTheFile() throws {
        let store = makeStore()
        try store.setPhoto(jpeg(width: 300, height: 300))
        store.resetAvatar()
        XCTAssertEqual(store.avatar, .initials)
        XCTAssertNil(store.photo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: avatarFile.path))
    }

    func testChoosingMascotDeletesThePhoto() throws {
        let store = makeStore()
        try store.setPhoto(jpeg(width: 300, height: 300))
        store.setMascot(.cheer)
        XCTAssertEqual(store.avatar, .mascot(.cheer))
        XCTAssertFalse(FileManager.default.fileExists(atPath: avatarFile.path))
        XCTAssertEqual(makeStore().avatar, .mascot(.cheer))
    }

    func testMissingPhotoFileFallsBackToInitials() throws {
        try makeStore().setPhoto(jpeg(width: 300, height: 300))
        try FileManager.default.removeItem(at: avatarFile)
        XCTAssertEqual(makeStore().avatar, .initials)
    }

    func testUnknownStoredAvatarMeansInitials() {
        defaults.set("mascot:dragon", forKey: SettingsKey.profileAvatar)
        XCTAssertEqual(makeStore().avatar, .initials)
    }

    // MARK: - Удаление

    func testEraseLocalRemovesThePhotoFolder() throws {
        try makeStore().setPhoto(jpeg(width: 300, height: 300))
        ProfileStore.eraseLocal(directory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testEraseLocalWithNothingSavedIsFine() {
        ProfileStore.eraseLocal(directory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}
