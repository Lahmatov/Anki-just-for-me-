import XCTest
@testable import AJFMCore

final class VoiceSelectorTests: XCTestCase {

    private func voice(
        _ id: String, _ language: String = "en-US",
        _ quality: VoiceQuality = .compact, name: String = "Voice"
    ) -> VoiceDescriptor {
        VoiceDescriptor(identifier: id, language: language, quality: quality, name: name)
    }

    func testPrefersPremiumOverEverything() {
        let voices = [
            voice("compact", "en-US", .compact),
            voice("premium", "en-US", .premium),
            voice("enhanced", "en-US", .enhanced),
        ]
        XCTAssertEqual(VoiceSelector.best(from: voices, language: "en-US")?.identifier, "premium")
    }

    func testFallsBackToEnhancedThenCompact() {
        let withEnhanced = [voice("a", "en-US", .compact), voice("b", "en-US", .enhanced)]
        XCTAssertEqual(
            VoiceSelector.best(from: withEnhanced, language: "en-US")?.identifier, "b")

        let onlyCompact = [voice("a", "en-US", .compact)]
        XCTAssertEqual(
            VoiceSelector.best(from: onlyCompact, language: "en-US")?.identifier, "a")
    }

    func testAmericanEnglishIsNotBritish() {
        // Учим американский — британский голос не подходит даже премиальный.
        let voices = [voice("uk", "en-GB", .premium), voice("us", "en-US", .compact)]
        XCTAssertEqual(VoiceSelector.best(from: voices, language: "en-US")?.identifier, "us")
    }

    func testLanguageMatchIgnoresCaseAndSeparator() {
        XCTAssertTrue(VoiceSelector.matches("en_US", "en-US"))
        XCTAssertTrue(VoiceSelector.matches("EN-us", "en-US"))
        XCTAssertFalse(VoiceSelector.matches("en-GB", "en-US"))
        XCTAssertFalse(VoiceSelector.matches("en", "en-US"))
    }

    func testChoiceIsStableBetweenLaunches() {
        // При равном качестве голос не должен прыгать от запуска к запуску.
        let voices = [
            voice("zulu", "en-US", .enhanced),
            voice("alpha", "en-US", .enhanced),
            voice("mike", "en-US", .enhanced),
        ]
        XCTAssertEqual(VoiceSelector.best(from: voices, language: "en-US")?.identifier, "alpha")
        XCTAssertEqual(
            VoiceSelector.best(from: voices.reversed(), language: "en-US")?.identifier, "alpha")
    }

    func testNoVoicesForLanguage() {
        XCTAssertNil(VoiceSelector.best(from: [voice("uk", "en-GB")], language: "en-US"))
        XCTAssertNil(VoiceSelector.best(from: [], language: "en-US"))
    }

    func testSuggestsDownloadOnlyWhenStuckWithCompact() {
        let compactOnly = [voice("a", "en-US", .compact)]
        XCTAssertTrue(VoiceSelector.shouldSuggestBetterVoice(from: compactOnly, language: "en-US"))

        let withEnhanced = compactOnly + [voice("b", "en-US", .enhanced)]
        XCTAssertFalse(
            VoiceSelector.shouldSuggestBetterVoice(from: withEnhanced, language: "en-US"))
    }

    func testNoSuggestionWhenLanguageIsMissingEntirely() {
        // Нечего предлагать скачивать, если голосов языка нет вовсе —
        // это другая проблема, и подсказка про качество только запутает.
        XCTAssertFalse(VoiceSelector.shouldSuggestBetterVoice(from: [], language: "en-US"))
    }

    func testQualityOrdering() {
        XCTAssertLessThan(VoiceQuality.compact, VoiceQuality.enhanced)
        XCTAssertLessThan(VoiceQuality.enhanced, VoiceQuality.premium)
    }

    func testSlowRateIsActuallySlower() {
        XCTAssertLessThan(SpeechRate.slow.multiplier, SpeechRate.normal.multiplier)
    }
}
