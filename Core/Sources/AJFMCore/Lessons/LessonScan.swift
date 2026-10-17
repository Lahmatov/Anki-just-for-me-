import Foundation

/// Текст урока, распознанный с фото или из PDF, — в вид, пригодный для запроса.
///
/// Распознавание отдаёт строки как они лежат на странице: с переносами
/// «pequeno-al-» / «moço», номерами страниц и колонтитулами, которые
/// повторяются на каждом листе. Модели это мешает меньше, чем человеку,
/// который видит текст в поле, — но лишнее ещё и стоит денег.
public enum LessonScan {

    /// Страницы по порядку, в каждой — строки сверху вниз.
    public static func clean(pages: [[String]]) -> String {
        let trimmed = pages.map { page in
            page.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        // Колонтитул — строка с края страницы (две первые или две последние),
        // которая повторяется на краю каждой страницы. Середину не трогаем:
        // слово урока может встретиться на всех листах.
        var repeated = Set<String>()
        if trimmed.count >= 2 {
            let edges = trimmed.map { page -> Set<String> in
                let lines = page.filter { !$0.isEmpty }
                return Set(lines.prefix(2) + lines.suffix(2))
            }
            repeated = edges.dropFirst().reduce(edges[0]) { $0.intersection($1) }
        }
        let text = trimmed.map { page in
            joinLines(page.filter { !repeated.contains($0) && !isNoise($0) })
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        return text.prefix(utf16: DeckRequest.lessonLimit)
    }

    public static func clean(lines: [String]) -> String {
        clean(pages: [lines])
    }

    /// Номер страницы («12», «p. 14», «стр. 3»), одинокие знаки — то, что не слово.
    static func isNoise(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        var rest = line.lowercased()
        for prefix in ["página", "pagina", "pág.", "pag.", "page", "p.", "стр.", "с."] // lint: не интерфейс
        where rest.hasPrefix(prefix) {
            rest = String(rest.dropFirst(prefix.count))
            break
        }
        return !rest.contains { $0.isLetter } && (rest.contains { $0.isNumber } || rest == line.lowercased())
    }

    /// Слово, разорванное переносом, склеивается обратно в одну строку.
    /// Дефис остаётся: распознавание не отличает перенос «al-/moço» от
    /// составного «pequeno-/almoço», а выброшенный дефис молча испортил бы
    /// составное слово. Лишний дефис модель уберёт сама — она чинит опечатки.
    /// Пустые строки сжимаются до одной.
    static func joinLines(_ lines: [String]) -> String {
        var result: [String] = []
        var blank = false
        for line in lines {
            if line.isEmpty {
                blank = !result.isEmpty
                continue
            }
            if let last = result.last, !blank, last.hasSuffix("-"),
               let first = line.first, first.isLowercase,
               last.dropLast().last?.isLetter == true {
                result[result.count - 1] = last + line
                continue
            }
            if blank { result.append("") }
            result.append(line)
            blank = false
        }
        return result.joined(separator: "\n")
    }
}
