import XCTest
@testable import AJFMCore

final class StudyLanguageTests: XCTestCase {

    func testUnknownOrEmptyStoredValueFallsBackToEnglish() {
        XCTAssertEqual(StudyLanguage.stored(nil), .english)
        XCTAssertEqual(StudyLanguage.stored(""), .english)
        XCTAssertEqual(StudyLanguage.stored("pt-BR"), .english)
        XCTAssertEqual(StudyLanguage.stored("klingon"), .english)
    }

    func testStoredValueRoundTrips() {
        for language in StudyLanguage.allCases {
            XCTAssertEqual(StudyLanguage.stored(language.rawValue), language)
        }
    }

    /// Всё, что накоплено до появления языков, живёт в базе по умолчанию.
    func testEnglishKeepsTheDefaultStore() {
        XCTAssertNil(StudyLanguage.english.storeName)
    }

    func testOtherLanguagesHaveTheirOwnDistinctStores() {
        let names = StudyLanguage.allCases.compactMap(\.storeName)
        XCTAssertEqual(names.count, StudyLanguage.allCases.count - 1)
        XCTAssertEqual(Set(names).count, names.count, "две базы в одном файле перемешали бы наборы")
    }

    func testEnglishKeysStayAsTheyWere() {
        XCTAssertEqual(StudyLanguage.english.scopedKey("celebratedStreak"), "celebratedStreak")
    }

    func testOtherLanguagesKeysDoNotCollide() {
        let keys = StudyLanguage.allCases.map { $0.scopedKey("celebratedStreak") }
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(StudyLanguage.portuguese.scopedKey("studyShow"), "pt-PT.studyShow")
    }

    func testBackupPrefixKeepsOldEnglishBackupsEnglish() {
        XCTAssertEqual(StudyLanguage.english.backupPrefix, "")
        XCTAssertEqual(StudyLanguage.italian.backupPrefix, "it-")
    }

    func testPortugueseIsEuropean() {
        XCTAssertEqual(StudyLanguage.portuguese.speechLocale, "pt-PT")
        XCTAssertTrue(StudyLanguage.portuguese.promptName.contains("Portugal"))
        XCTAssertTrue(StudyLanguage.portuguese.promptName.contains("never Brazilian"))
    }

    func testSpeechLocalesAreDistinct() {
        let locales = StudyLanguage.allCases.map(\.speechLocale)
        XCTAssertEqual(Set(locales).count, locales.count)
    }

    /// Каталог и тест уровня — про английский: у других языков их прячем.
    func testEnglishOnlyFeatures() {
        XCTAssertTrue(StudyLanguage.english.hasShowCatalog)
        XCTAssertFalse(StudyLanguage.portuguese.hasShowCatalog)
        XCTAssertFalse(StudyLanguage.italian.hasPlacementTest)
    }
}

final class TranslationLanguageTests: XCTestCase {
    func testTranslationsGoIntoTheInterfaceLanguage() {
        XCTAssertEqual(StudyLanguage.portuguese.translationLanguage(for: .russian), .russian)
        XCTAssertEqual(StudyLanguage.italian.translationLanguage(for: .portuguese), .portuguese)
    }

    func testPortugueseIsNotTranslatedIntoItself() {
        XCTAssertEqual(StudyLanguage.portuguese.translationLanguage(for: .portuguese), .english)
    }

    /// Английский с английским интерфейсом — толкования, как и раньше.
    func testEnglishWithEnglishInterfaceStaysEnglish() {
        XCTAssertEqual(StudyLanguage.english.translationLanguage(for: .english), .english)
    }
}
