import XCTest
@testable import AJFMCore

final class BackupFileTests: XCTestCase {
    private func sampleBackup(exportedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> BackupFile {
        BackupFile(
            exportedAt: exportedAt,
            decks: [
                BackupDeck(
                    name: "Breaking Bad S03E05",
                    folder: "Сериалы/Breaking Bad",
                    scheduler: .fsrs6,
                    cardTypes: [.recognition, .recall],
                    source: "сериал",
                    createdAt: Date(timeIntervalSince1970: 1_600_000_000),
                    notes: [
                        BackupNote(
                            data: NoteData(term: "leverage", translation: "рычаг", ipa: "/ˈlevərɪdʒ/"),
                            createdAt: Date(timeIntervalSince1970: 1_600_000_100),
                            cards: [
                                BackupCard(
                                    type: .recognition,
                                    due: Date(timeIntervalSince1970: 1_700_100_000),
                                    intervalDays: 21,
                                    reps: 7,
                                    lapses: 1,
                                    state: "review",
                                    schedulerState: "{\"difficulty\":5.2}"
                                )
                            ]
                        )
                    ]
                )
            ]
        )
    }

    func testRoundTripPreservesEverything() throws {
        let original = sampleBackup()
        let restored = try BackupCoder.decode(try BackupCoder.encode(original))
        XCTAssertEqual(restored, original)
    }

    func testRoundTripPreservesCardProgress() throws {
        let restored = try BackupCoder.decode(try BackupCoder.encode(sampleBackup()))
        let card = try XCTUnwrap(restored.decks.first?.notes.first?.cards.first)
        // Главное, ради чего бэкап и существует: прогресс повторений переживает переезд.
        XCTAssertEqual(card.intervalDays, 21)
        XCTAssertEqual(card.reps, 7)
        XCTAssertEqual(card.lapses, 1)
        XCTAssertEqual(card.state, "review")
        XCTAssertEqual(card.schedulerState, "{\"difficulty\":5.2}")
    }

    func testStampsFormatAndVersion() throws {
        let backup = sampleBackup()
        XCTAssertEqual(backup.format, BackupFile.formatID)
        XCTAssertEqual(backup.version, BackupFile.supportedVersion)
    }

    func testDatesSurviveAsISO8601() throws {
        let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let data = try BackupCoder.encode(sampleBackup(exportedAt: exportedAt))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("2023-11-14"), "дата должна быть читаемой, а не числом")
        XCTAssertEqual(try BackupCoder.decode(data).exportedAt, exportedAt)
    }

    func testNoteCountAcrossDecks() {
        let backup = BackupFile(exportedAt: Date(), decks: [
            sampleBackup().decks[0], sampleBackup().decks[0]
        ])
        XCTAssertEqual(backup.noteCount, 2)
    }

    func testEmptyBackupIsValid() throws {
        let empty = BackupFile(exportedAt: Date(timeIntervalSince1970: 0), decks: [])
        XCTAssertEqual(try BackupCoder.decode(try BackupCoder.encode(empty)), empty)
        XCTAssertEqual(empty.noteCount, 0)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try BackupCoder.decode(Data("не json".utf8)))
    }
}
