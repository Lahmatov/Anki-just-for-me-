import XCTest
@testable import AJFMCore

final class SentenceMinerTests: XCTestCase {

    private func track(_ lines: [String]) -> SubtitleTrack {
        SubtitleTrack(cues: lines.enumerated().map { index, text in
            SubtitleCue(
                index: index + 1, start: Double(index) * 10,
                end: Double(index) * 10 + 3, text: text)
        })
    }

    func testFindsSentenceWithTheWord() throws {
        let subtitles = track([
            "Nothing happens here.",
            "You have no leverage at all.",
            "Goodbye.",
        ])
        let mined = try XCTUnwrap(SentenceMiner.bestSentence(for: "leverage", in: subtitles))
        XCTAssertEqual(mined.sentence, "You have no leverage at all.")
        XCTAssertEqual(mined.timecode, 10, accuracy: 0.001)
    }

    func testPrefersShorterSentence() throws {
        let subtitles = track([
            "I think that in this particular situation you really have no leverage whatsoever here.",
            "You have no leverage.",
        ])
        let mined = try XCTUnwrap(SentenceMiner.bestSentence(for: "leverage", in: subtitles))
        // Короткая фраза запоминается лучше и помещается на карточку.
        XCTAssertEqual(mined.sentence, "You have no leverage.")
    }

    func testSkipsTooShortFragments() {
        let subtitles = track(["Leverage.", "Yeah."])
        XCTAssertNil(SentenceMiner.bestSentence(for: "leverage", in: subtitles))
    }

    func testSkipsOverlyLongLines() {
        let long = Array(repeating: "word", count: 25).joined(separator: " ") + " leverage"
        XCTAssertNil(SentenceMiner.bestSentence(for: "leverage", in: track([long])))
    }

    func testMissingWordGivesNothing() {
        XCTAssertNil(SentenceMiner.bestSentence(for: "космос", in: track(["Hello there friend."])))
    }

    func testMinesSeveralTermsAtOnce() {
        let subtitles = track([
            "You have no leverage here.",
            "Don't back out on me now.",
            "Nothing to see here.",
        ])
        let mined = SentenceMiner.mine(terms: ["leverage", "back out", "космос"], in: subtitles)
        XCTAssertEqual(mined.count, 2)
        XCTAssertNotNil(mined["leverage"])
        XCTAssertNil(mined["космос"])
    }

    // MARK: - Пропуски

    func testClozeReplacesExactWord() {
        let cloze = SentenceMiner.makeCloze(
            sentence: "You have no leverage at all.", term: "leverage")
        XCTAssertEqual(cloze, "You have no ___ at all.")
    }

    func testClozeIsCaseInsensitive() {
        let cloze = SentenceMiner.makeCloze(
            sentence: "Leverage is everything.", term: "leverage")
        XCTAssertEqual(cloze, "___ is everything.")
    }

    func testClozeHandlesInflectedForms() {
        // В субтитрах слово почти всегда стоит в другой форме.
        let cloze = SentenceMiner.makeCloze(
            sentence: "I can't believe you pulled that off.", term: "pull")
        XCTAssertEqual(cloze, "I can't believe you ___ that off.")
    }

    func testClozeIgnoresInfinitiveParticle() {
        let cloze = SentenceMiner.makeCloze(
            sentence: "You have no leverage.", term: "to leverage")
        XCTAssertEqual(cloze, "You have no ___.")
    }

    func testClozeReplacesOnlyTheFirstMatch() {
        let cloze = SentenceMiner.makeCloze(
            sentence: "Leverage means leverage.", term: "leverage")
        XCTAssertEqual(cloze, "___ means leverage.")
    }

    func testSentenceWithoutTheWordStaysIntact() {
        let sentence = "Nothing matches here."
        XCTAssertEqual(SentenceMiner.makeCloze(sentence: sentence, term: "leverage"), sentence)
    }

    func testTooShortStemIsNotGuessed() {
        // По двум буквам угадывать опасно: «go» совпало бы с «got», «gone», «good».
        let sentence = "I am good today."
        XCTAssertEqual(SentenceMiner.makeCloze(sentence: sentence, term: "go"), sentence)
    }

    func testEmptyTermIsHandled() {
        let sentence = "Anything at all."
        XCTAssertEqual(SentenceMiner.makeCloze(sentence: sentence, term: ""), sentence)
    }

    func testMinedClozeMatchesTheSentence() throws {
        let subtitles = track(["I can't believe you pulled that off."])
        let mined = try XCTUnwrap(SentenceMiner.bestSentence(for: "pull off", in: subtitles))
        XCTAssertTrue(mined.cloze.contains("___"))
        XCTAssertNotEqual(mined.cloze, mined.sentence)
    }
}
