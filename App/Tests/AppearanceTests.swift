import XCTest
import SwiftUI
import UIKit
@testable import AJFM

/// Тема интерфейса: три варианта и их перевод для SwiftUI и UIKit.
final class AppearanceTests: XCTestCase {

    func testSystemLeavesTheChoiceToIOS() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.system.interfaceStyle, .unspecified)
    }

    func testLightAndDarkAreForced() {
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
        XCTAssertEqual(AppAppearance.light.interfaceStyle, .light)
        XCTAssertEqual(AppAppearance.dark.interfaceStyle, .dark)
    }

    /// Испорченная настройка не должна оставить человека с чужой темой.
    func testUnknownStoredValueMeansSystem() {
        XCTAssertEqual(AppAppearance.stored(nil), .system)
        XCTAssertEqual(AppAppearance.stored(""), .system)
        XCTAssertEqual(AppAppearance.stored("sepia"), .system)
        XCTAssertEqual(AppAppearance.stored("dark"), .dark)
    }

    func testEveryOptionHasATitleAndSymbol() {
        for option in AppAppearance.allCases {
            XCTAssertFalse(option.title.isEmpty)
            XCTAssertFalse(option.symbol.isEmpty)
        }
    }

    @MainActor
    func testApplyingToWindowsDoesNotCrashWithoutWindows() {
        // В тестах окон может не быть — применение темы должно молча пройти.
        AppAppearance.dark.applyToWindows()
        AppAppearance.system.applyToWindows()
    }
}

/// Тема разговора с Мончиком: серия или урок.
@MainActor
final class DiscussionTopicTests: XCTestCase {
    func testLessonTopicTitleIsTheLessonName() {
        let topic = DiscussionTopic.lesson(LessonTopic(title: "Aula 5", terms: ["comer"]))
        XCTAssertEqual(topic.title, "Aula 5")
        XCTAssertNotEqual(topic, .lesson(LessonTopic(title: "Aula 6", terms: ["comer"])))
    }
}
