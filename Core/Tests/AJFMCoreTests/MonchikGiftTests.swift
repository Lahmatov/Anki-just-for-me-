import XCTest
@testable import AJFMCore

final class MonchikGiftTests: XCTestCase {

    func testEveryMilestoneHasExactlyOneGift() {
        let milestones = Journey.stops.filter(Journey.isMilestone)
        XCTAssertEqual(milestones.count, MonchikGifts.all.count)
        for stop in milestones {
            XCTAssertNotNil(MonchikGifts.gift(at: stop), "веха \(stop.threshold) без подарка")
        }
    }

    func testOrdinaryStopsHaveNoGift() {
        for stop in Journey.stops where !Journey.isMilestone(stop) {
            XCTAssertNil(MonchikGifts.gift(at: stop), "\(stop.threshold)")
        }
    }

    func testGiftsAreUniqueAndOrdered() {
        XCTAssertEqual(Set(MonchikGifts.all.map(\.id)).count, MonchikGifts.all.count)
        XCTAssertEqual(Set(MonchikGifts.all.map(\.emoji)).count, MonchikGifts.all.count)
        XCTAssertEqual(MonchikGifts.all.map(\.words), MonchikGifts.all.map(\.words).sorted())
    }

    func testEveryGiftHasAName() {
        for gift in MonchikGifts.all {
            XCTAssertNotEqual(gift.name, gift.id, "у \(gift.id) нет перевода")
        }
    }

    func testUnlockedGrowsWithWords() {
        XCTAssertEqual(MonchikGifts.unlocked(words: 99), [])
        XCTAssertEqual(MonchikGifts.unlocked(words: 100).map(\.id), ["scarf"])
        XCTAssertEqual(MonchikGifts.unlocked(words: 600).map(\.id), ["scarf", "headphones", "popcorn"])
        XCTAssertEqual(MonchikGifts.unlocked(words: 50_000).count, MonchikGifts.all.count)
    }

    func testNewestGiftIsWornByDefault() {
        XCTAssertEqual(MonchikGifts.equipped(chosen: nil, words: 600)?.id, "popcorn")
        XCTAssertNil(MonchikGifts.equipped(chosen: nil, words: 10))
    }

    func testChosenGiftIsWorn() {
        XCTAssertEqual(MonchikGifts.equipped(chosen: "scarf", words: 600)?.id, "scarf")
    }

    func testLockedChoiceFallsBackToNewestOpen() {
        // Слова удалили — корона «вернулась в сундук», носим лучшее из открытого.
        XCTAssertEqual(MonchikGifts.equipped(chosen: "crown", words: 300)?.id, "headphones")
    }

    func testTakenOffStaysOff() {
        XCTAssertNil(MonchikGifts.equipped(chosen: MonchikGifts.takenOff, words: 5000))
    }

    func testUnknownChoiceFallsBack() {
        XCTAssertEqual(MonchikGifts.equipped(chosen: "jetpack", words: 150)?.id, "scarf")
    }
}
