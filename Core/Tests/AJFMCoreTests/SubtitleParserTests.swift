import XCTest
@testable import AJFMCore

final class SubtitleParserTests: XCTestCase {

    private let srt = """
    1
    00:00:01,000 --> 00:00:04,000
    You have no leverage at all.

    2
    00:00:05,500 --> 00:00:08,000
    I can't believe you
    pulled that off.

    3
    00:01:00,000 --> 00:01:02,000
    <i>Don't back out now.</i>
    """

    func testParsesBasicSRT() throws {
        let track = try SubtitleParser.parse(srt)
        XCTAssertEqual(track.cues.count, 3)
        XCTAssertEqual(track.cues[0].text, "You have no leverage at all.")
        XCTAssertEqual(track.cues[0].start, 1, accuracy: 0.001)
        XCTAssertEqual(track.cues[0].end, 4, accuracy: 0.001)
    }

    func testJoinsMultiLineCue() throws {
        let track = try SubtitleParser.parse(srt)
        XCTAssertEqual(track.cues[1].text, "I can't believe you pulled that off.")
    }

    func testStripsFormattingTags() throws {
        let track = try SubtitleParser.parse(srt)
        XCTAssertEqual(track.cues[2].text, "Don't back out now.")
    }

    func testStripsPositioningBraces() {
        XCTAssertEqual(SubtitleParser.clean("{\\an8}Hello there"), "Hello there")
        XCTAssertEqual(SubtitleParser.clean("<font color=\"#fff\">Hi</font>"), "Hi")
    }

    func testHandlesWindowsLineEndings() throws {
        let windows = srt.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(try SubtitleParser.parse(windows).cues.count, 3)
    }

    func testParsesWebVTT() throws {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        You have no leverage.

        00:00:05.000 --> 00:00:07.000 align:start position:10%
        Don't back out.
        """
        let track = try SubtitleParser.parse(vtt)
        XCTAssertEqual(track.cues.count, 2)
        XCTAssertEqual(track.cues[1].text, "Don't back out.")
        XCTAssertEqual(track.cues[1].start, 5, accuracy: 0.001)
    }

    func testTimestampFormats() {
        XCTAssertEqual(SubtitleParser.parseTimestamp("00:01:23,456") ?? 0, 83.456, accuracy: 0.001)
        XCTAssertEqual(SubtitleParser.parseTimestamp("01:23.456") ?? 0, 83.456, accuracy: 0.001)
        XCTAssertEqual(SubtitleParser.parseTimestamp("01:02:03,000") ?? 0, 3723, accuracy: 0.001)
        XCTAssertNil(SubtitleParser.parseTimestamp("бред"))
        XCTAssertNil(SubtitleParser.parseTimestamp(""))
    }

    func testEmptyFileIsRejected() {
        XCTAssertThrowsError(try SubtitleParser.parse("   \n\n ")) { error in
            XCTAssertEqual(error as? SubtitleParseError, .empty)
        }
    }

    func testFileWithoutTimingsIsRejected() {
        XCTAssertThrowsError(try SubtitleParser.parse("просто текст без таймкодов")) { error in
            XCTAssertEqual(error as? SubtitleParseError, .noCues)
        }
    }

    func testSkipsBrokenBlocksButKeepsGoodOnes() throws {
        let broken = """
        1
        битый таймкод
        Пропущенная реплика

        2
        00:00:05,000 --> 00:00:07,000
        Хорошая реплика
        """
        let track = try SubtitleParser.parse(broken)
        XCTAssertEqual(track.cues.count, 1)
        XCTAssertEqual(track.cues[0].text, "Хорошая реплика")
    }

    func testCuesAreRenumberedSequentially() throws {
        let track = try SubtitleParser.parse(srt)
        XCTAssertEqual(track.cues.map(\.index), [1, 2, 3])
    }

    func testDurationIsTheLastCueEnd() throws {
        XCTAssertEqual(try SubtitleParser.parse(srt).duration, 62, accuracy: 0.001)
    }

    // MARK: - Текст для разбора

    func testPlainTextJoinsEverything() throws {
        let text = try SubtitleParser.parse(srt).plainText()
        XCTAssertTrue(text.contains("leverage"))
        XCTAssertTrue(text.contains("pulled that off"))
        XCTAssertTrue(text.contains("back out"))
    }

    func testTrimmingByTimecodePreventsSpoilers() throws {
        // Досмотрел до 10-й секунды — разбор не должен знать, что было дальше.
        let text = try SubtitleParser.parse(srt).plainText(upTo: 10)
        XCTAssertTrue(text.contains("leverage"))
        XCTAssertFalse(text.contains("back out"), "реплика из будущего не должна попасть в эталон")
    }

    func testTrimmingAtZeroGivesNothing() throws {
        XCTAssertEqual(try SubtitleParser.parse(srt).plainText(upTo: 0), "")
    }

    // MARK: - Поиск фраз для карточек

    func testFindsCuesContainingAWord() throws {
        let track = try SubtitleParser.parse(srt)
        let found = track.cues(containing: "leverage")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].index, 1)
    }

    func testSearchIgnoresCaseAndArticles() throws {
        let track = try SubtitleParser.parse(srt)
        XCTAssertEqual(track.cues(containing: "LEVERAGE").count, 1)
        XCTAssertEqual(track.cues(containing: "to back out").count, 1,
                       "«to» не должно мешать найти фразовый глагол")
    }

    func testSearchForMissingWordReturnsNothing() throws {
        let track = try SubtitleParser.parse(srt)
        XCTAssertTrue(track.cues(containing: "космос").isEmpty)
        XCTAssertTrue(track.cues(containing: "").isEmpty)
    }
}
