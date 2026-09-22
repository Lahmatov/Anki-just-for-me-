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
                                    review: ReviewState(
                                        state: .review,
                                        due: Date(timeIntervalSince1970: 1_700_100_000),
                                        lastReview: Date(timeIntervalSince1970: 1_698_284_000),
                                        intervalDays: 21,
                                        reps: 7,
                                        lapses: 1,
                                        stability: 34.5,
                                        difficulty: 5.2
                                    )
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
        XCTAssertEqual(card.review.intervalDays, 21)
        XCTAssertEqual(card.review.reps, 7)
        XCTAssertEqual(card.review.lapses, 1)
        XCTAssertEqual(card.review.state, .review)
        XCTAssertEqual(card.review.stability, 34.5)
        XCTAssertEqual(card.review.difficulty, 5.2)
        XCTAssertTrue(card.review.isMature, "21 день — это уже выученное слово")
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

    func testRejectsForeignFormat() throws {
        // Восстановление заменяет базу целиком, поэтому чужой файл должен
        // отсекаться до того, как что-то будет удалено.
        let deckFile = try DeckParser.encode(DeckFile(
            deck: DeckMeta(name: "Набор"),
            notes: [NoteData(term: "word", translation: "слово")]))
        XCTAssertThrowsError(try BackupCoder.decode(deckFile)) { error in
            XCTAssertEqual(error as? BackupError, .wrongFormat(found: DeckFile.formatID))
        }
    }

    func testRejectsNewerVersion() throws {
        var data = try BackupCoder.encode(sampleBackup())
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
            .replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 99")
        data = Data(text.utf8)
        XCTAssertThrowsError(try BackupCoder.decode(data)) { error in
            XCTAssertEqual(
                error as? BackupError,
                .unsupportedVersion(found: 99, supported: BackupFile.supportedVersion))
        }
    }
}
