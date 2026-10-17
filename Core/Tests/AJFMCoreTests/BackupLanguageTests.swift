import XCTest
@testable import AJFMCore

final class BackupLanguageTests: XCTestCase {

    func testOldBackupWithoutLanguageIsEnglish() throws {
        let json = """
        {"format":"ajfm-backup","version":1,"exportedAt":"2026-09-01T10:00:00Z","decks":[]}
        """
        let backup = try BackupCoder.decode(Data(json.utf8))
        XCTAssertNil(backup.language)
        XCTAssertEqual(backup.studyLanguage, .english)
    }

    func testLanguageSurvivesARoundTrip() throws {
        let backup = BackupFile(exportedAt: Date(timeIntervalSince1970: 1_800_000_000), decks: [],
                                language: StudyLanguage.portuguese.rawValue)
        let decoded = try BackupCoder.decode(try BackupCoder.encode(backup))
        XCTAssertEqual(decoded.studyLanguage, .portuguese)
    }

    func testUnknownLanguageFallsBackToEnglish() {
        let backup = BackupFile(exportedAt: Date(), decks: [], language: "xx")
        XCTAssertEqual(backup.studyLanguage, .english)
    }

    func testEnglishFileNameKeepsTheOldShape() {
        XCTAssertEqual(BackupFileName.make(stamp: "2026-10-17-1200", language: .english),
                       "ajfm-2026-10-17-1200.json")
    }

    func testEachLanguageOwnsOnlyItsFiles() {
        let english = BackupFileName.make(stamp: "2026-10-17-1200", language: .english)
        let portuguese = BackupFileName.make(stamp: "2026-10-17-1200", language: .portuguese)
        let italian = BackupFileName.make(stamp: "2026-10-17-1200", language: .italian)

        XCTAssertTrue(BackupFileName.belongs(english, to: .english))
        XCTAssertFalse(BackupFileName.belongs(portuguese, to: .english))
        XCTAssertFalse(BackupFileName.belongs(italian, to: .english))

        XCTAssertTrue(BackupFileName.belongs(portuguese, to: .portuguese))
        XCTAssertFalse(BackupFileName.belongs(english, to: .portuguese))
        XCTAssertFalse(BackupFileName.belongs(italian, to: .portuguese))
    }

    func testForeignFilesBelongToNobody() {
        for language in StudyLanguage.allCases {
            XCTAssertFalse(BackupFileName.belongs("notes.json", to: language))
            XCTAssertFalse(BackupFileName.belongs("ajfm-log.txt", to: language))
        }
    }
}
