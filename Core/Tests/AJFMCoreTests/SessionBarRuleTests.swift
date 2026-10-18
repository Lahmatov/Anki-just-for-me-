import XCTest
@testable import AJFMCore

final class SessionBarRuleTests: XCTestCase {
    private typealias Rule = SessionBarRule<String>

    /// Сессия открыта со «Сегодня»: путь из одного экрана.
    private func openSession(in stack: String = "today", depth: Int = 1) -> Rule {
        var rule = Rule()
        rule.sessionAppeared(stack: stack, depth: depth, currentDepth: depth)
        return rule
    }

    func testBarIsVisibleWithoutSession() {
        XCTAssertFalse(Rule().isBarHidden)
    }

    func testOpenSessionHidesBar() {
        XCTAssertTrue(openSession().isBarHidden)
    }

    func testClosedSessionShowsBar() {
        var rule = openSession()
        rule.sessionDisappeared()
        XCTAssertFalse(rule.isBarHidden)
    }

    func testBackButtonShowsBarEvenWithoutDisappear() {
        var rule = openSession()
        rule.pathChanged(stack: "today", depth: 0)
        XCTAssertFalse(rule.isBarHidden)
    }

    /// Случай с iPhone 17: «исчез», затем запоздалое «появился» у той же сессии.
    func testLateAppearAfterBackDoesNotHideBar() {
        var rule = openSession()
        rule.pathChanged(stack: "today", depth: 0)
        rule.sessionDisappeared()
        rule.sessionAppeared(stack: "today", depth: 1, currentDepth: 0)
        XCTAssertFalse(rule.isBarHidden)
    }

    func testLateAppearBeforePathChangeIsUndoneByPathChange() {
        var rule = openSession()
        rule.sessionDisappeared()
        rule.sessionAppeared(stack: "today", depth: 1, currentDepth: 1)
        rule.pathChanged(stack: "today", depth: 0)
        XCTAssertFalse(rule.isBarHidden)
    }

    func testSessionAtStackRootDoesNotHideBar() {
        var rule = Rule()
        rule.sessionAppeared(stack: "today", depth: 0, currentDepth: 0)
        XCTAssertFalse(rule.isBarHidden)
    }

    func testPushingDeeperKeepsBarHidden() {
        var rule = openSession()
        rule.pathChanged(stack: "today", depth: 2)
        XCTAssertTrue(rule.isBarHidden)
    }

    func testOtherStackPathDoesNotShowBar() {
        // Лист со своим стеком поверх сессии закрылся — сессия ещё открыта.
        var rule = openSession(in: "today")
        rule.pathChanged(stack: "sheet", depth: 0)
        XCTAssertTrue(rule.isBarHidden)
    }

    /// Recap: сессия слов — третий экран пути, назад к шагам Recap.
    func testDeepSessionClosesWhenPathShrinksBelowIt() {
        var rule = openSession(depth: 3)
        rule.pathChanged(stack: "today", depth: 2)
        XCTAssertFalse(rule.isBarHidden)
    }

    func testSessionOutsideStackHidesUntilDisappear() {
        var rule = Rule()
        rule.sessionAppeared(stack: nil, depth: nil, currentDepth: nil)
        XCTAssertTrue(rule.isBarHidden)
        rule.sessionDisappeared()
        XCTAssertFalse(rule.isBarHidden)
    }
}
