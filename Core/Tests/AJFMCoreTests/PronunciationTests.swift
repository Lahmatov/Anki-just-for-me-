import XCTest
@testable import AJFMCore

final class PronunciationEvaluatorTests: XCTestCase {

    func testExactMatchWithHighConfidenceIsAccepted() {
        let result = PronunciationEvaluator.evaluate(
            expected: "leverage", recognized: "leverage", confidence: 0.9)
        XCTAssertEqual(result.verdict, .matched)
        XCTAssertTrue(result.isAccepted)
        XCTAssertTrue(result.isReliable)
    }

    func testMatchWithLowConfidenceIsAcceptedButHonestlyLabelled() {
        let result = PronunciationEvaluator.evaluate(
            expected: "leverage", recognized: "leverage", confidence: 0.45)
        XCTAssertEqual(result.verdict, .matched)
        XCTAssertFalse(result.isReliable)
        // Никаких «Отлично!»: распознаватель подгоняет услышанное под словарь,
        // и совпадение при низкой уверенности ничего не гарантирует.
        XCTAssertTrue(result.message.contains("не уверен"))
    }

    func testDifferentWordWithGoodConfidenceIsARealSignal() {
        let result = PronunciationEvaluator.evaluate(
            expected: "work", recognized: "walk", confidence: 0.85)
        XCTAssertEqual(result.verdict, .mismatched)
        XCTAssertFalse(result.isAccepted)
        XCTAssertTrue(result.isReliable)
        XCTAssertTrue(result.message.contains("walk"))
    }

    func testDifferentWordWithLowConfidenceBlamesTheRecording() {
        // Не штрафуем за то, что могло быть шумом или плохим микрофоном.
        let result = PronunciationEvaluator.evaluate(
            expected: "work", recognized: "wok", confidence: 0.1)
        XCTAssertEqual(result.verdict, .unclear)
        XCTAssertFalse(result.isReliable)
    }

    func testEmptyRecognitionIsUnclear() {
        let result = PronunciationEvaluator.evaluate(
            expected: "work", recognized: "", confidence: 0.9)
        XCTAssertEqual(result.verdict, .unclear)
        XCTAssertFalse(result.isReliable)
    }

    func testCaseAndPunctuationDoNotMatter() {
        let result = PronunciationEvaluator.evaluate(
            expected: "leverage", recognized: "  Leverage.  ", confidence: 0.9)
        XCTAssertEqual(result.verdict, .matched)
    }

    func testArticlesAndInfinitiveAreIgnored() {
        let result = PronunciationEvaluator.evaluate(
            expected: "to pull off", recognized: "pull off", confidence: 0.8)
        XCTAssertEqual(result.verdict, .matched)
    }

    func testAlternativesArePreserved() {
        let result = PronunciationEvaluator.evaluate(
            expected: "ship", recognized: "sheep", confidence: 0.7,
            alternatives: ["ship", "cheap"])
        XCTAssertEqual(result.alternatives, ["ship", "cheap"])
    }

    func testDisclaimerNeverPromisesCertainty() {
        // Текст читает живой человек и делает по нему выводы о своём произношении.
        XCTAssertTrue(PronunciationEvaluator.onDeviceDisclaimer.contains("мягкая"))
        XCTAssertFalse(PronunciationEvaluator.onDeviceDisclaimer.contains("Отлично"))
    }
}

final class MinimalPairsTests: XCTestCase {

    func testLibraryIsNotEmptyAndWellFormed() {
        let pairs = MinimalPairLibrary.all
        XCTAssertGreaterThan(pairs.count, 10)

        for pair in pairs {
            XCTAssertFalse(pair.first.isEmpty)
            XCTAssertFalse(pair.second.isEmpty)
            XCTAssertNotEqual(pair.first, pair.second)
            XCTAssertFalse(pair.contrast.isEmpty, "\(pair.id): не указан контраст звуков")
            XCTAssertFalse(pair.hint.isEmpty, "\(pair.id): нет подсказки, как различать")
        }
    }

    func testEveryPairHasAHintInEveryLanguage() {
        defer { Loc.language = .russian }
        for language in AppLanguage.allCases {
            Loc.language = language
            for pair in MinimalPairLibrary.all {
                XCTAssertFalse(pair.hint.isEmpty, "\(pair.id), \(language)")
            }
        }
    }

    func testPairIdentifiersAreUnique() {
        let ids = MinimalPairLibrary.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testCoversTheClassicRussianTraps() {
        let pairs = MinimalPairLibrary.all
        let contrasts = pairs.map(\.contrast).joined(separator: " ")
        // Межзубные, различение долгих и кратких гласных, /v/ против /w/ —
        // три главные беды русскоязычного произношения.
        XCTAssertTrue(contrasts.contains("θ"), "нет межзубного глухого")
        XCTAssertTrue(contrasts.contains("ð"), "нет межзубного звонкого")
        XCTAssertTrue(contrasts.contains("w"), "нет различения /v/ и /w/")
        XCTAssertTrue(contrasts.contains("æ"), "нет открытого /æ/")
        XCTAssertTrue(contrasts.contains("ɪ"), "нет краткого /ɪ/")
    }

    func testFindingAPairByEitherWord() {
        XCTAssertEqual(MinimalPairLibrary.pair(containing: "ship")?.second, "sheep")
        XCTAssertEqual(MinimalPairLibrary.pair(containing: "sheep")?.first, "ship")
        XCTAssertEqual(MinimalPairLibrary.pair(containing: "SHIP")?.second, "sheep")
        XCTAssertNil(MinimalPairLibrary.pair(containing: "leverage"))
    }

    func testOtherWordInPair() {
        let pair = MinimalPair("ship", "sheep", contrast: "x", ru: "y", pt: "y", en: "y")
        XCTAssertEqual(pair.other(than: "ship"), "sheep")
        XCTAssertEqual(pair.other(than: "sheep"), "ship")
        XCTAssertEqual(pair.other(than: "Ship"), "sheep")
    }

    func testSayingTheRightWordIsAccepted() throws {
        let pair = try XCTUnwrap(MinimalPairLibrary.pair(containing: "ship"))
        let result = MinimalPairLibrary.evaluate(
            pair: pair, target: "ship", recognized: "ship", confidence: 0.8)
        XCTAssertEqual(result.verdict, .matched)
        XCTAssertTrue(result.isReliable)
    }

    func testSayingTheOppositeWordIsTheHonestFailure() throws {
        let pair = try XCTUnwrap(MinimalPairLibrary.pair(containing: "ship"))
        let result = MinimalPairLibrary.evaluate(
            pair: pair, target: "ship", recognized: "sheep", confidence: 0.8)

        // Ради этого случая минимальные пары и нужны: распознаватель выбрал
        // соседнее слово, а значит звук действительно прозвучал иначе.
        XCTAssertEqual(result.verdict, .mismatched)
        XCTAssertTrue(result.isReliable)
        XCTAssertTrue(result.message.contains(pair.contrast))
        XCTAssertTrue(result.message.contains(pair.hint))
    }

    func testThirdWordMeansBadRecording() throws {
        let pair = try XCTUnwrap(MinimalPairLibrary.pair(containing: "ship"))
        let result = MinimalPairLibrary.evaluate(
            pair: pair, target: "ship", recognized: "shop", confidence: 0.8)
        XCTAssertEqual(result.verdict, .unclear)
        XCTAssertFalse(result.isReliable, "чужое слово ничего не говорит о нужном звуке")
    }

    func testSilenceIsHandled() throws {
        let pair = try XCTUnwrap(MinimalPairLibrary.pair(containing: "ship"))
        let result = MinimalPairLibrary.evaluate(
            pair: pair, target: "ship", recognized: "", confidence: 0)
        XCTAssertEqual(result.verdict, .unclear)
        XCTAssertTrue(result.message.contains("не разобрал"))
    }
}
