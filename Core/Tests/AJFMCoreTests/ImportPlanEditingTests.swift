import XCTest
@testable import AJFMCore

final class ImportPlanEditingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Loc.language = .russian
    }

    override func tearDown() {
        Loc.language = .russian
        super.tearDown()
    }

    private func plan(words: Int = 3) -> ImportPlan {
        ImportPlanner.plan(
            file: DeckFile(
                deck: DeckMeta(name: "Friends", folder: "Claude"),
                notes: (1...words).map { NoteData(term: "w\($0)", translation: "t") }),
            existingTerms: [:])
    }

    func testEditsAreApplied() {
        let edited = plan().edited(
            name: "  S01E03 · The One  ", folder: "Сериалы / Friends / Сезон 1",
            scheduler: .leitner, cardTypes: [.recognition, .listening])
        XCTAssertEqual(edited.deckName, "S01E03 · The One")
        XCTAssertEqual(edited.folderPath, ["Сериалы", "Friends", "Сезон 1"])
        XCTAssertEqual(edited.scheduler, .leitner)
        XCTAssertEqual(edited.cardTypes, [.recognition, .listening])
    }

    func testBlankNameKeepsTheOldOne() {
        let edited = plan().edited(name: "   ", folder: "", scheduler: .fsrs6,
                                   cardTypes: [.recognition])
        XCTAssertEqual(edited.deckName, "Friends")
    }

    func testEmptyFolderMeansRoot() {
        let edited = plan().edited(name: "X", folder: " / ", scheduler: .fsrs6,
                                   cardTypes: [.recognition])
        XCTAssertEqual(edited.folderPath, [])
        XCTAssertEqual(edited.folderText, "")
    }

    func testNoCardTypesKeepsThePrevious() {
        // Набор без единого вида карточек был бы пустым.
        let original = plan()
        let edited = original.edited(name: "X", folder: "", scheduler: .fsrs6, cardTypes: [])
        XCTAssertEqual(edited.cardTypes, original.cardTypes)
    }

    func testCardTypeOrderIsCanonical() {
        let edited = plan().edited(name: "X", folder: "", scheduler: .fsrs6,
                                   cardTypes: [.cloze, .recall, .recognition])
        XCTAssertEqual(edited.cardTypes, [.recognition, .recall, .cloze])
    }

    func testTotalCardsFollowTheChosenTypes() {
        let edited = plan(words: 43).edited(name: "X", folder: "", scheduler: .fsrs6,
                                            cardTypes: [.recognition])
        XCTAssertEqual(edited.totalCards, 43)
    }

    func testWordsAreUntouchedByEdits() {
        let original = plan()
        let edited = original.edited(name: "Y", folder: "Z", scheduler: .sm2,
                                     cardTypes: [.spelling])
        XCTAssertEqual(edited.newNotes, original.newNotes)
        XCTAssertEqual(edited.duplicates, original.duplicates)
    }

    func testFolderTextRoundTrips() {
        let path = ["Сериалы", "Friends"]
        var p = plan()
        p.folderPath = path
        XCTAssertEqual(ImportPlan.folderPath(from: p.folderText), path)
    }

    func testCardsExplanationAnswersWhyThereAreTwiceAsManyCards() {
        XCTAssertEqual(ImportPlan.cardsExplanation(words: 43, types: 2),
                       "43 слова × 2 вида = 86 карточек")
        XCTAssertEqual(ImportPlan.cardsExplanation(words: 0, types: 2),
                       "0 слов × 2 вида = 0 карточек")
        XCTAssertEqual(ImportPlan.cardsExplanation(words: -1, types: -5),
                       "0 слов × 0 видов = 0 карточек")
    }

    func testEveryCardTypeAndSchedulerIsExplained() {
        for type in CardType.allCases { XCTAssertFalse(type.explanation.isEmpty, type.rawValue) }
        for id in SchedulerID.allCases { XCTAssertFalse(id.explanation.isEmpty, id.rawValue) }
    }

    func testCoverTravelsFromTheFileToThePlan() {
        let withCover = ImportPlanner.plan(
            file: DeckFile(
                deck: DeckMeta(name: "X", cover: "https://static.tvmaze.com/p.jpg"),
                notes: [NoteData(term: "a", translation: "b")]),
            existingTerms: [:])
        XCTAssertEqual(withCover.coverURL, "https://static.tvmaze.com/p.jpg")
        XCTAssertNil(plan().coverURL)
    }

    func testCoverSurvivesTheNormalizerUnderAliases() throws {
        let file = try DeckParser.parse(string: """
        { "name": "X", "poster": "https://example.com/p.jpg",
          "notes": [ { "term": "a", "translation": "b" } ] }
        """)
        XCTAssertEqual(file.deck.cover, "https://example.com/p.jpg")
    }
}
