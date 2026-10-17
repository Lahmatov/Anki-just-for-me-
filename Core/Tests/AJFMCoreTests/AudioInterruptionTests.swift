import XCTest
@testable import AJFMCore

final class AudioInterruptionTests: XCTestCase {
    private func whileRecording(_ event: AudioEvent) -> AudioReaction {
        AudioInterruptionPolicy.reaction(to: event, isRecording: true, isPlaying: false)
    }

    private func whilePlaying(_ event: AudioEvent) -> AudioReaction {
        AudioInterruptionPolicy.reaction(to: event, isRecording: false, isPlaying: true)
    }

    func testPhoneCallFinishesRecordingKeepingText() {
        XCTAssertEqual(whileRecording(.interruptionBegan), .finishKeepingText)
    }

    func testRecordingNeverResumesByItself() {
        XCTAssertEqual(whileRecording(.interruptionEnded(shouldResume: true)), .ignore)
    }

    func testLostHeadsetOrNewMicrophoneFinishesRecording() {
        XCTAssertEqual(whileRecording(.deviceLost), .finishKeepingText)
        XCTAssertEqual(whileRecording(.configurationChanged), .finishKeepingText)
    }

    func testBackgroundAndMediaResetFinishRecording() {
        XCTAssertEqual(whileRecording(.appDidEnterBackground), .finishKeepingText)
        XCTAssertEqual(whileRecording(.mediaServicesReset), .finishKeepingText)
    }

    func testUnpluggedHeadphonesSilencePlayback() {
        XCTAssertEqual(whilePlaying(.deviceLost), .stopPlayback)
    }

    func testCallSilencesPlaybackAndItStaysSilent() {
        XCTAssertEqual(whilePlaying(.interruptionBegan), .stopPlayback)
        XCTAssertEqual(whilePlaying(.interruptionEnded(shouldResume: true)), .ignore)
    }

    func testIdleIgnoresEverything() {
        let events: [AudioEvent] = [.interruptionBegan, .interruptionEnded(shouldResume: false), .deviceLost,
                                    .configurationChanged, .mediaServicesReset, .appDidEnterBackground]
        for event in events {
            XCTAssertEqual(AudioInterruptionPolicy.reaction(to: event, isRecording: false, isPlaying: false),
                           .ignore, event.logName)
        }
    }

    func testRecordingWinsOverPlayback() {
        XCTAssertEqual(AudioInterruptionPolicy.reaction(to: .deviceLost, isRecording: true, isPlaying: true),
                       .finishKeepingText)
    }
}
