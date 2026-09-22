import XCTest
@testable import AJFMCore

/// Сверка порта FSRS-6 с эталонной реализацией py-fsrs.
///
/// Векторы сгенерированы из py-fsrs (коммит 9446cb0) с выключенным разбросом
/// интервалов — файл `Resources/fsrs6-vectors.json`. Планирование повторений
/// нельзя проверить на глаз: интервал «вроде вырос» ничего не доказывает.
/// Поэтому единственный честный критерий — побитовое совпадение с эталоном.
final class FSRS6ReferenceTests: XCTestCase {

    private struct Vectors: Decodable {
        let source: String
        let startDate: String
        let defaultParameters: [Double]
        let cases: [Case]
    }

    private struct Case: Decodable {
        let name: String
        let retention: Double
        let steps: [Step]
    }

    private struct Step: Decodable {
        let grade: Int
        let gapDays: Double
        let after: Snapshot
    }

    private struct Snapshot: Decodable {
        let state: String
        let step: Int?
        let stability: Double?
        let difficulty: Double?
        let dueOffsetSeconds: Double
    }

    private func loadVectors() throws -> Vectors {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "fsrs6-vectors", withExtension: "json", subdirectory: "Resources"),
            "не найден файл с эталонными векторами")
        return try JSONDecoder().decode(Vectors.self, from: try Data(contentsOf: url))
    }

    private var startDate: Date {
        // 2026-01-01 12:00:00 UTC — та же точка отсчёта, что в генераторе векторов.
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    func testDefaultParametersMatchReference() throws {
        let vectors = try loadVectors()
        XCTAssertEqual(vectors.defaultParameters.count, 21)
        for (index, expected) in vectors.defaultParameters.enumerated() {
            XCTAssertEqual(
                FSRS6Scheduler.defaultParameters[index], expected, accuracy: 1e-12,
                "параметр w[\(index)] разошёлся с эталоном")
        }
    }

    func testEveryReferenceCaseMatches() throws {
        let vectors = try loadVectors()
        XCTAssertFalse(vectors.cases.isEmpty)

        var checkedSteps = 0
        for testCase in vectors.cases {
            let scheduler = FSRS6Scheduler(
                desiredRetention: testCase.retention, enableFuzzing: false)
            var state = ReviewState()
            var now = startDate

            for (index, step) in testCase.steps.enumerated() {
                now = now.addingTimeInterval(step.gapDays * 86_400)
                let grade = try XCTUnwrap(Grade(rawValue: step.grade))
                state = scheduler.review(state, grade: grade, now: now)

                let label = "\(testCase.name), шаг \(index + 1)"
                XCTAssertEqual(state.state.rawValue, step.after.state, "состояние — \(label)")
                XCTAssertEqual(state.step, step.after.step, "шаг заучивания — \(label)")
                assertEqual(state.stability, step.after.stability, "устойчивость — \(label)")
                assertEqual(state.difficulty, step.after.difficulty, "сложность — \(label)")
                XCTAssertEqual(
                    state.due.timeIntervalSince(now), step.after.dueOffsetSeconds,
                    accuracy: 0.001, "срок следующего показа — \(label)")
                checkedSteps += 1
            }
        }
        XCTAssertGreaterThan(checkedSteps, 80, "векторы должны покрывать десятки шагов")
    }

    private func assertEqual(
        _ actual: Double?, _ expected: Double?, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch (actual, expected) {
        case (nil, nil):
            break
        case let (actual?, expected?):
            XCTAssertEqual(actual, expected, accuracy: 1e-9, message, file: file, line: line)
        default:
            XCTFail("\(message): получено \(String(describing: actual)), "
                    + "ожидалось \(String(describing: expected))", file: file, line: line)
        }
    }
}
