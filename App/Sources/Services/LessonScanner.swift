import Foundation
import Vision
import PDFKit
import UIKit
import AJFMCore

/// Текст урока с фото и из PDF (P-69). Распознаётся на телефоне: снимок
/// страницы никуда не уходит, в запрос попадает только текст — его видно
/// и можно поправить в поле до отправки.
enum LessonScanner {

    enum Failure: LocalizedError {
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return tr("Не получилось открыть файл.", "Não foi possível abrir o ficheiro.",
                          "Couldn't open the file.")
            case .empty:
                return tr("На странице не нашлось текста. Сними поближе и при хорошем свете.",
                          "Não encontrei texto na página. Fotografa mais de perto e com boa luz.",
                          "No text found on the page. Shoot closer and in good light.")
            }
        }
    }

    /// Страниц PDF за раз: урок — это пара листов, а не учебник.
    static let pageLimit = 20

    static func text(fromImages images: [Data], language: StudyLanguage) async throws -> String {
        var pages: [[String]] = []
        for data in images.prefix(pageLimit) {
            pages.append(try await lines(in: data, language: language))
        }
        return try finish(pages)
    }

    static func text(fromPDF url: URL, language: StudyLanguage) async throws -> String {
        guard let document = PDFDocument(url: url) else { throw Failure.unreadable }
        var pages: [[String]] = []
        for index in 0..<min(document.pageCount, pageLimit) {
            guard let page = document.page(at: index) else { continue }
            let embedded = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if embedded.count >= 20 {
                pages.append(embedded.components(separatedBy: .newlines))
            } else if let data = page.thumbnail(of: CGSize(width: 1600, height: 2200), for: .mediaBox)
                .jpegData(compressionQuality: 0.9) {
                // Скан без текстового слоя — распознаём картинку страницы.
                pages.append(try await lines(in: data, language: language))
            }
        }
        return try finish(pages)
    }

    private static func finish(_ pages: [[String]]) throws -> String {
        let text = LessonScan.clean(pages: pages)
        guard !text.isEmpty else { throw Failure.empty }
        return text
    }

    /// Строки страницы сверху вниз. Языки — изучаемый, русский и английский:
    /// в конспекте рядом стоят слово и его перевод.
    private static func lines(in data: Data, language: StudyLanguage) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data), let cgImage = image.cgImage else {
                throw Failure.unreadable
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = [language.speechLocale, "ru-RU", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: LessonScanner.orientation(of: image))
            try handler.perform([request])
            let observations = request.results ?? []
            // У Vision начало координат внизу: выше на странице — больше y.
            return observations
                .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                .compactMap { $0.topCandidates(1).first?.string }
        }.value
    }

    static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
