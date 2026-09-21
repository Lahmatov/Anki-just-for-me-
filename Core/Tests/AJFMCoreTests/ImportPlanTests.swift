import XCTest
@testable import AJFMCore

final class ImportPlanTests: XCTestCase {
    private func file(
        folder: String? = nil,
        cardTypes: [CardType]? = nil,
        scheduler: SchedulerID? = nil,
        terms: [String]
    ) -> DeckFile {
        DeckFile(
            deck: DeckMeta(
                name: "Набор", folder: folder, scheduler: scheduler, cardTypes: cardTypes),
            notes: terms.map { NoteData(term: $0, translation: "перевод") }
        )
    }

    func testDefaultsWhenDeckOmitsThem() {
        let plan = ImportPlanner.plan(file: file(terms: ["one"]), existingTerms: [:])
        XCTAssertEqual(plan.scheduler, .fsrs6)
        XCTAssertEqual(plan.cardTypes, ImportPlanner.defaultCardTypes)
        XCTAssertTrue(plan.folderPath.isEmpty)
    }

    func testFolderPathIsSplit() {
        let plan = ImportPlanner.plan(
            file: file(folder: "Сериалы/Breaking Bad", terms: ["one"]), existingTerms: [:])
        XCTAssertEqual(plan.folderPath, ["Сериалы", "Breaking Bad"])
    }

    func testFolderPathIgnoresEmptySegments() {
        let plan = ImportPlanner.plan(
            file: file(folder: "/A//B/ ", terms: ["one"]), existingTerms: [:])
        XCTAssertEqual(plan.folderPath, ["A", "B"])
    }

    func testDuplicateWithinFileIsCaughtOnce() {
        let plan = ImportPlanner.plan(
            file: file(terms: ["pull off", "To Pull Off", "leverage"]), existingTerms: [:])
        XCTAssertEqual(plan.newNotes.map(\.term), ["pull off", "leverage"])
        XCTAssertEqual(plan.duplicates.count, 1)
        XCTAssertNil(plan.duplicates[0].existingDeckName)
    }

    func testDuplicateAgainstDatabaseNamesTheDeck() {
        let plan = ImportPlanner.plan(
            file: file(terms: ["leverage", "new word"]),
            existingTerms: ["leverage": "Старый набор"])
        XCTAssertEqual(plan.newNotes.map(\.term), ["new word"])
        XCTAssertEqual(plan.duplicates.count, 1)
        XCTAssertEqual(plan.duplicates[0].existingDeckName, "Старый набор")
        XCTAssertEqual(plan.duplicates[0].reason, "уже есть в наборе «Старый набор»")
    }

    func testCardCountMultipliesByTypes() {
        let plan = ImportPlanner.plan(
            file: file(cardTypes: [.recognition, .recall, .listening], terms: ["a1", "b2", "c3"]),
            existingTerms: [:])
        XCTAssertEqual(plan.totalCards, 9)
    }

    func testDuplicateCardTypesAreCollapsed() {
        let plan = ImportPlanner.plan(
            file: file(cardTypes: [.recall, .recall, .recognition], terms: ["one"]),
            existingTerms: [:])
        XCTAssertEqual(plan.cardTypes, [.recall, .recognition])
    }

    func testWarnsAboutClozeWithoutClozeField() {
        let plan = ImportPlanner.plan(
            file: file(cardTypes: [.cloze], terms: ["one", "two"]), existingTerms: [:])
        XCTAssertEqual(plan.warnings.count, 1)
        XCTAssertTrue(plan.warnings[0].contains("2 слов"))
    }

    func testWarnsAboutOversizedDeck() {
        let terms = (1...40).map { "word\($0)" }
        let plan = ImportPlanner.plan(file: file(terms: terms), existingTerms: [:])
        XCTAssertEqual(plan.newNotes.count, 40)
        XCTAssertTrue(plan.warnings.contains { $0.contains("40 новых слов") })
    }

    func testSkipsTermsThatNormalizeToNothing() {
        let plan = ImportPlanner.plan(file: file(terms: ["...", "real"]), existingTerms: [:])
        XCTAssertEqual(plan.newNotes.map(\.term), ["real"])
        XCTAssertEqual(plan.warnings.count, 1)
    }
}
