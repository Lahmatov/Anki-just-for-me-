import XCTest
@testable import AJFMCore

final class ToneSynthTests: XCTestCase {

    func testLengthMatchesTheLastNote() {
        let samples = ToneSynth.render([Tone(frequency: 440, start: 0.1, duration: 0.2)], sampleRate: 1000)
        XCTAssertEqual(samples.count, 300)
    }

    func testSilenceBeforeTheNoteStarts() {
        let samples = ToneSynth.render([Tone(frequency: 440, start: 0.1, duration: 0.2)], sampleRate: 1000)
        XCTAssertTrue(samples.prefix(100).allSatisfy { $0 == 0 })
        XCTAssertTrue(samples.dropFirst(100).contains { $0 != 0 })
    }

    func testNoteStartsAndEndsSilentlyNoClick() {
        let samples = ToneSynth.render([Tone(frequency: 440, start: 0, duration: 0.2)])
        XCTAssertEqual(samples.first ?? 1, 0, accuracy: 0.001)
        XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.01)
    }

    func testChordNeverClips() {
        let loud = (0..<8).map { Tone(frequency: 200 + Double($0) * 50, start: 0, duration: 0.3, volume: 1) }
        let peak = ToneSynth.render(loud).map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(peak, 0.951)
    }

    func testBrokenTonesAreSkipped() {
        let broken = [Tone(frequency: 0, start: 0, duration: 1),
                      Tone(frequency: 440, start: 0, duration: -1),
                      Tone(frequency: 440, start: -1, duration: 1)]
        XCTAssertEqual(ToneSynth.render(broken), [])
    }

    func testNoTonesNoSamples() {
        XCTAssertEqual(ToneSynth.render([]), [])
    }

    func testEnvelopeIsZeroOutsideTheNote() {
        XCTAssertEqual(ToneSynth.envelope(-0.1, 1), 0)
        XCTAssertEqual(ToneSynth.envelope(1.1, 1), 0)
        XCTAssertEqual(ToneSynth.envelope(0.5, 0), 0)
    }

    func testEveryCueIsShortAndAudible() {
        for cue in SoundCue.allCases {
            XCTAssertGreaterThan(cue.duration, 0, cue.rawValue)
            XCTAssertLessThanOrEqual(cue.duration, 1.2, "\(cue.rawValue): звук не должен тянуться")
            let samples = ToneSynth.render(cue.tones)
            XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.05, cue.rawValue)
        }
    }

    func testWrongIsQuieterAndLowerThanCorrect() {
        // Ошибка не должна звучать громче и резче успеха — за неё не ругают.
        let peak = { (cue: SoundCue) in ToneSynth.render(cue.tones).map(abs).max() ?? 0 }
        XCTAssertLessThan(peak(.wrong), peak(.correct))
        let lowest = { (cue: SoundCue) in cue.tones.map(\.frequency).min() ?? 0 }
        XCTAssertLessThan(lowest(.wrong), lowest(.correct))
    }
}
