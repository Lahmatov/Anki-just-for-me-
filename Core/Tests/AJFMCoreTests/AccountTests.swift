import XCTest
@testable import AJFMCore

final class LegalDocumentTests: XCTestCase {

    override func tearDown() {
        Loc.language = .russian
        super.tearDown()
    }

    // MARK: - Выбор файла

    func testTranslatedDocumentsFollowTheAppLanguage() {
        XCTAssertEqual(LegalDocument.resourceName(.terms, language: .portuguese), "terms.pt")
        XCTAssertEqual(LegalDocument.resourceName(.privacy, language: .russian), "privacy.ru")
    }

    func testLicensesAreAlwaysEnglish() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(LegalDocument.resourceName(.licenses, language: language), "licenses.en")
        }
    }

    // MARK: - Данные продавца

    private let seller = LegalDocument.Seller(
        name: "Ana Silva", address: "Rua 1, Lisboa", email: "help@example.pt")

    func testFillReplacesEveryPlaceholder() {
        let text = "CONTROLLER_NAME, CONTROLLER_ADDRESS. Write to CONTACT_EMAIL or CONTACT_EMAIL."
        XCTAssertEqual(LegalDocument.fill(text, seller: seller),
                       "Ana Silva, Rua 1, Lisboa. Write to help@example.pt or help@example.pt.")
    }

    func testFillKeepsPlaceholderWhenValueIsNotSetYet() {
        let unset = LegalDocument.Seller(name: "CHANGE-ME", address: " ", email: "help@example.pt")
        XCTAssertEqual(LegalDocument.fill("CONTROLLER_NAME / CONTROLLER_ADDRESS / CONTACT_EMAIL",
                                          seller: unset),
                       "CONTROLLER_NAME / CONTROLLER_ADDRESS / help@example.pt")
    }

    func testSellerIsCompleteOnlyWithAllThreeFields() {
        XCTAssertTrue(seller.isComplete)
        var partial = seller
        partial.address = "CHANGE-ME"
        XCTAssertFalse(partial.isComplete)
    }

    func testContactEmailRejectsPlaceholderAndGarbage() {
        XCTAssertEqual(seller.contactEmail, "help@example.pt")
        for bad in ["CHANGE-ME@example.com", "", "no-at-sign", "a@b", "a b@c.pt"] {
            XCTAssertNil(LegalDocument.Seller(name: "x", address: "y", email: bad).contactEmail, bad)
        }
    }

    // MARK: - Разбор

    func testParsesHeadingsParagraphsAndRules() {
        let blocks = LegalDocument.parse("""
        # Title

        First line
        continues here.

        ## Section
        ---
        """)
        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Title"),
            .paragraph("First line continues here."),
            .heading(level: 2, text: "Section"),
            .rule,
        ])
    }

    func testHashWithoutSpaceIsNotAHeading() {
        XCTAssertEqual(LegalDocument.parse("#hashtag"), [.paragraph("#hashtag")])
    }

    func testParsesBulletsWithContinuationLines() {
        let blocks = LegalDocument.parse("""
        - one
          still one
        * two
        """)
        XCTAssertEqual(blocks, [.bullet("one still one"), .bullet("two")])
    }

    func testParsesNumberedItems() {
        XCTAssertEqual(LegalDocument.parse("1. First\n2. Second"),
                       [.numbered(1, "First"), .numbered(2, "Second")])
    }

    func testYearAtLineStartIsNotANumberedItem() {
        XCTAssertEqual(LegalDocument.parse("2026 was a year."), [.paragraph("2026 was a year.")])
    }

    func testParsesTableAndSkipsSeparatorRow() {
        let blocks = LegalDocument.parse("""
        | Data | Kept |
        |---|:---:|
        | Device ID | 12 months |
        | Usage | 90 days |

        After.
        """)
        XCTAssertEqual(blocks, [
            .table([["Data", "Kept"], ["Device ID", "12 months"], ["Usage", "90 days"]]),
            .paragraph("After."),
        ])
    }

    func testTableRightAfterParagraphStartsANewBlock() {
        let blocks = LegalDocument.parse("Intro\n| a | b |")
        XCTAssertEqual(blocks, [.paragraph("Intro"), .table([["a", "b"]])])
    }

    func testKeepsEmptyTableCells() {
        XCTAssertEqual(LegalDocument.parse("| a | | c |"), [.table([["a", "", "c"]])])
    }

    func testWindowsLineEndingsAreHandled() {
        XCTAssertEqual(LegalDocument.parse("# T\r\n\r\ntext"),
                       [.heading(level: 1, text: "T"), .paragraph("text")])
    }

    func testEmptyInputGivesNoBlocks() {
        XCTAssertEqual(LegalDocument.parse(""), [])
        XCTAssertEqual(LegalDocument.parse("\n\n   \n"), [])
    }

    func testEmptyBulletMarkerIsTreatedAsText() {
        XCTAssertEqual(LegalDocument.parse("-"), [.paragraph("-")])
    }

    // MARK: - Настоящие документы из docs/legal

    /// docs/legal рядом с репозиторием: Core/Tests/AJFMCoreTests/этот файл → корень.
    private var legalDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/legal", directoryHint: .isDirectory)
    }

    private func document(_ kind: LegalDocument.Kind, _ language: AppLanguage) throws -> String {
        let name = LegalDocument.resourceName(kind, language: language)
        return try String(contentsOf: legalDirectory.appending(path: name + ".md"), encoding: .utf8)
    }

    func testEveryDocumentExistsInEveryLanguage() throws {
        for kind in LegalDocument.Kind.allCases {
            for language in AppLanguage.allCases {
                let blocks = LegalDocument.parse(try document(kind, language))
                guard case .heading(1, _)? = blocks.first else {
                    return XCTFail("\(kind) \(language): документ должен начинаться с заголовка")
                }
                XCTAssertGreaterThan(blocks.count, 10, "\(kind) \(language)")
            }
        }
    }

    func testDocumentsUseOnlyKnownPlaceholders() throws {
        let known: Set<String> = ["CONTROLLER_NAME", "CONTROLLER_ADDRESS", "CONTACT_EMAIL"]
        let pattern = try NSRegularExpression(pattern: "\\b[A-Z]+_[A-Z_]+\\b")
        for kind in LegalDocument.Kind.allCases where kind.isTranslated {
            for language in AppLanguage.allCases {
                let text = try document(kind, language)
                let found = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
                XCTAssertTrue(Set(found).isSubset(of: known),
                              "\(kind) \(language): неизвестные метки \(Set(found).subtracting(known))")
            }
        }
    }

    func testFilledDocumentsHaveNoPlaceholdersLeft() throws {
        let seller = LegalDocument.Seller(name: "Ana Silva", address: "Rua 1, Lisboa",
                                          email: "help@example.pt")
        for language in AppLanguage.allCases {
            let filled = LegalDocument.fill(try document(.privacy, language), seller: seller)
            XCTAssertFalse(filled.contains("CONTROLLER_"), "\(language)")
            XCTAssertFalse(filled.contains("CONTACT_EMAIL"), "\(language)")
            XCTAssertTrue(filled.contains("Ana Silva"), "\(language)")
        }
    }

    func testTranslationsKeepTheSameStructure() throws {
        // Переводы не должны терять разделы: юридически все версии равны.
        for kind in LegalDocument.Kind.allCases where kind.isTranslated {
            let counts = try AppLanguage.allCases.map { language in
                LegalDocument.parse(try document(kind, language)).filter {
                    if case .heading = $0 { return true } else { return false }
                }.count
            }
            XCTAssertEqual(Set(counts).count, 1, "\(kind): разное число разделов \(counts)")
        }
    }
}

final class ProfileTests: XCTestCase {

    func testInitialsFromTwoWords() {
        XCTAssertEqual(ProfileName.initials("egor lahmatov"), "EL")
    }

    func testInitialsUseOnlyTheFirstTwoWords() {
        XCTAssertEqual(ProfileName.initials("Ana Maria Silva"), "AM")
    }

    func testInitialsFromCyrillicName() {
        XCTAssertEqual(ProfileName.initials("мончик"), "М")
    }

    func testInitialsSkipWordsWithoutLetters() {
        XCTAssertEqual(ProfileName.initials("🦌 42 Egor"), "E")
    }

    func testInitialsOfEmptyNameAreEmpty() {
        XCTAssertEqual(ProfileName.initials("   "), "")
    }

    func testCleanCollapsesWhitespaceAndLimitsLength() {
        XCTAssertEqual(ProfileName.clean("  Ana \n  Silva  "), "Ana Silva")
        XCTAssertEqual(ProfileName.clean(String(repeating: "a", count: 100)).count, ProfileName.maxLength)
    }

    func testNameFromAppleSignIn() {
        XCTAssertEqual(ProfileName.from(givenName: "Ana", familyName: "Silva"), "Ana Silva")
        XCTAssertEqual(ProfileName.from(givenName: "Ana", familyName: nil), "Ana")
    }

    func testNoNameFromAppleOnRepeatSignIn() {
        // Apple отдаёт имя только при первом входе — дальше поля пустые.
        XCTAssertNil(ProfileName.from(givenName: nil, familyName: nil))
        XCTAssertNil(ProfileName.from(givenName: " ", familyName: ""))
    }

    // MARK: - Аватарка

    func testCenterSquareOfLandscapePhoto() {
        XCTAssertEqual(AvatarGeometry.centerSquare(width: 4000, height: 3000),
                       AvatarGeometry.Square(x: 500, y: 0, side: 3000))
    }

    func testCenterSquareOfPortraitPhoto() {
        XCTAssertEqual(AvatarGeometry.centerSquare(width: 300, height: 500),
                       AvatarGeometry.Square(x: 0, y: 100, side: 300))
    }

    func testBrokenImageHasNoSquare() {
        XCTAssertNil(AvatarGeometry.centerSquare(width: 0, height: 100))
        XCTAssertNil(AvatarGeometry.centerSquare(width: -1, height: 100))
        XCTAssertNil(AvatarGeometry.centerSquare(width: .nan, height: 100))
    }

    func testLargePhotoIsScaledDownButSmallIsNotScaledUp() {
        XCTAssertEqual(AvatarGeometry.outputSide(for: 3000), AvatarGeometry.maxSide)
        XCTAssertEqual(AvatarGeometry.outputSide(for: 200), 200)
        XCTAssertEqual(AvatarGeometry.outputSide(for: 0), 0)
    }
}

final class SupportMailTests: XCTestCase {

    override func tearDown() {
        Loc.language = .russian
        super.tearDown()
    }

    func testMailtoCarriesEncodedSubjectAndBody() throws {
        let url = try XCTUnwrap(SupportMail.url(to: "help@example.pt", subject: "Recap: вопрос",
                                                body: "line 1\nA+B"))
        XCTAssertEqual(url.scheme, "mailto")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "help@example.pt")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["subject"], "Recap: вопрос")
        XCTAssertEqual(items["body"], "line 1\nA+B")
        XCTAssertTrue(url.absoluteString.contains("A%2BB"), "«+» не должен превратиться в пробел")
    }

    func testNoMailtoForBadAddress() {
        XCTAssertNil(SupportMail.url(to: "CONTACT_EMAIL", subject: "s", body: "b"))
        XCTAssertNil(SupportMail.url(to: "", subject: "s", body: "b"))
    }

    func testBodyHasVersionAndSupportCode() {
        Loc.language = .english
        let body = SupportMail.body(appVersion: "0.1 (1)", systemVersion: "26.0",
                                    supportCode: "AB12-CD34", language: .english)
        XCTAssertTrue(body.contains("Recap 0.1 (1) · iOS 26.0 · en"))
        XCTAssertTrue(body.contains("Support code: AB12-CD34"))
    }

    func testBodyWithoutSupportCodeOmitsTheLine() {
        let body = SupportMail.body(appVersion: "1", systemVersion: "26", supportCode: nil,
                                    language: .russian)
        XCTAssertFalse(body.contains("Код поддержки"))
    }
}

final class AccountAPITests: XCTestCase {

    override func tearDown() {
        Loc.language = .russian
        super.tearDown()
    }

    func testProfileStatusCarriesSignedIn() throws {
        let json = #"{"plan":"promo","active":true,"unitsTotal":10,"unitsLeft":5,"periodEnd":null,"signedIn":true,"supportCode":"AB12-CD34"}"#
        let status = try JSONDecoder().decode(BackendAPI.PlanStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.signedIn, true)
        XCTAssertEqual(status.supportCode, "AB12-CD34")
    }

    func testPlanStatusWithoutSignedInStillDecodes() throws {
        let json = #"{"plan":"none","active":false,"unitsTotal":0,"unitsLeft":0,"periodEnd":null}"#
        let status = try JSONDecoder().decode(BackendAPI.PlanStatus.self, from: Data(json.utf8))
        XCTAssertNil(status.signedIn)
    }

    func testSignInBodyHasTheFieldsTheServerExpects() throws {
        let data = try JSONEncoder().encode(BackendAPI.SignInBody(
            identityToken: "t", authorizationCode: "c", nonce: "n"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["identityToken": "t", "authorizationCode": "c", "nonce": "n"])
    }

    func testDecodesServerExport() throws {
        let json = """
        {"supportCode":"AB12-CD34","exportedAt":"2026-09-30T10:00:00.000Z",
         "device":{"registeredAt":"2026-09-01T00:00:00.000Z","lastSeenAt":"2026-09-30T00:00:00.000Z"},
         "account":null,
         "plan":{"plan":"none","active":false,"unitsTotal":0,"unitsLeft":0,"periodEnd":null,
                 "subscriptionProduct":null,"hasTransactionId":false},
         "episodes":[{"showId":431,"season":1,"episode":3,"at":"2026-09-02T00:00:00.000Z"}],
         "usage":[{"kind":"deck","inputTokens":100,"outputTokens":50,"at":"2026-09-02T00:00:00.000Z"},
                  {"kind":"discuss","inputTokens":10,"outputTokens":5,"at":"2026-09-02T00:00:00.000Z"}],
         "retentionDays":{"inactiveDevice":365,"usageLog":90}}
        """
        let export = try JSONDecoder().decode(BackendAPI.ServerExport.self, from: Data(json.utf8))
        XCTAssertEqual(export.supportCode, "AB12-CD34")
        XCTAssertNil(export.account)
        XCTAssertEqual(export.episodes.first?.showId, 431)
        XCTAssertEqual(export.totalTokens, 165)
    }

    func testAccountErrorsHaveHumanMessages() {
        Loc.language = .english
        for code in ["invalid_identity_token", "invalid_authorization_code", "signin_not_configured",
                     "apple_unavailable", "not_signed_in"] {
            let message = BackendAPI.Failure.server(code: code, status: 400).errorDescription ?? ""
            XCTAssertFalse(message.contains("(\(code))"), "для \(code) нужен свой текст")
        }
    }
}
