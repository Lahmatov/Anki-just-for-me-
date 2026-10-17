import XCTest
import UIKit
import AJFMCore
@testable import AJFM

/// Распознавание урока с картинки и из PDF (P-69) — настоящим Vision и
/// PDFKit на симуляторе: страница рисуется в тесте, её текст известен.
final class LessonScannerTests: XCTestCase {

    private let lines = ["Lesson 5 Travel", "book a flight", "the luggage"]

    private func pageImage(_ lines: [String]) -> Data {
        let size = CGSize(width: 1200, height: 900)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .medium),
                .foregroundColor: UIColor.black,
            ]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 60, y: 80 + CGFloat(index) * 140),
                                        withAttributes: attributes)
            }
        }
        return image.pngData()!
    }

    private func pdf(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "lesson-\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 18)]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 50, y: 60 + CGFloat(index) * 30), withAttributes: attributes)
            }
        }
        return url
    }

    func testTextIsReadFromAPhotoTopToBottom() async throws {
        let text = try await LessonScanner.text(fromImages: [pageImage(lines)], language: .english)
        let lower = text.lowercased()
        XCTAssertTrue(lower.contains("book a flight"), text)
        XCTAssertTrue(lower.contains("luggage"), text)
        let first = try XCTUnwrap(lower.range(of: "travel"))
        let last = try XCTUnwrap(lower.range(of: "luggage"))
        XCTAssertLessThan(first.lowerBound, last.lowerBound, "строки должны идти сверху вниз")
    }

    func testPDFWithATextLayerIsReadWithoutRecognition() async throws {
        let url = try pdf(lines)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try await LessonScanner.text(fromPDF: url, language: .english)
        XCTAssertTrue(text.contains("book a flight"), text)
        XCTAssertTrue(text.contains("the luggage"), text)
    }

    func testBlankPageSaysThereIsNoText() async {
        do {
            _ = try await LessonScanner.text(fromImages: [pageImage([])], language: .portuguese)
            XCTFail("пустая страница не должна давать текст")
        } catch let failure as LessonScanner.Failure {
            XCTAssertEqual(failure, .empty)
        } catch {
            XCTFail("не та ошибка: \(error)")
        }
    }

    func testBrokenImageIsReported() async {
        do {
            _ = try await LessonScanner.text(fromImages: [Data("not an image".utf8)], language: .english)
            XCTFail("мусор не должен распознаваться")
        } catch let failure as LessonScanner.Failure {
            XCTAssertEqual(failure, .unreadable)
        } catch {
            XCTFail("не та ошибка: \(error)")
        }
    }

    func testMissingPDFIsReported() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "nope-\(UUID().uuidString).pdf")
        do {
            _ = try await LessonScanner.text(fromPDF: url, language: .english)
            XCTFail("несуществующий PDF не должен читаться")
        } catch let failure as LessonScanner.Failure {
            XCTAssertEqual(failure, .unreadable)
        } catch {
            XCTFail("не та ошибка: \(error)")
        }
    }

    func testFailuresHaveHumanMessages() {
        XCTAssertFalse((LessonScanner.Failure.empty.errorDescription ?? "").isEmpty)
        XCTAssertFalse((LessonScanner.Failure.unreadable.errorDescription ?? "").isEmpty)
    }
}
