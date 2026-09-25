import Foundation

public struct SubtitleCue: Equatable, Sendable {
    public var index: Int
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(index: Int, start: TimeInterval, end: TimeInterval, text: String) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct SubtitleTrack: Equatable, Sendable {
    public var cues: [SubtitleCue]

    public init(cues: [SubtitleCue]) {
        self.cues = cues
    }

    public var duration: TimeInterval { cues.last?.end ?? 0 }
    public var isEmpty: Bool { cues.isEmpty }

    /// Сплошной текст — то, что уходит в разбор пересказа как эталон.
    /// - Parameter upTo: обрезка по таймкоду. Нужна, чтобы разбор не сослался
    ///   на события после момента, до которого ты досмотрел.
    public func plainText(upTo limit: TimeInterval? = nil) -> String {
        cues
            .filter { limit == nil || $0.start < limit! }
            .map(\.text)
            .joined(separator: " ")
    }

    /// Реплики, содержащие слово, — для sentence mining: примеры в карточках
    /// должны быть живыми фразами из уже просмотренной серии.
    public func cues(containing word: String) -> [SubtitleCue] {
        let needle = TermNormalizer.normalize(word)
        guard !needle.isEmpty else { return [] }
        return cues.filter { cue in
            TermNormalizer.normalize(cue.text).contains(needle)
        }
    }
}

public enum SubtitleParseError: Error, Equatable, LocalizedError {
    case empty
    case noCues

    public var errorDescription: String? {
        switch self {
        case .empty:
            return tr("Файл субтитров пуст.", "O ficheiro de legendas está vazio.",
                      "The subtitle file is empty.")
        case .noCues:
            return tr("В файле не нашлось ни одной реплики с таймкодами.",
                      "O ficheiro não tem nenhuma fala com marcas de tempo.",
                      "The file has no lines with timecodes.")
        }
    }
}

/// Разбор субтитров в форматах SRT и WebVTT.
///
/// Нужен для двух вещей: эталона при разборе пересказа (без него модель
/// начинает выдумывать твои ошибки — см. docs/retell.md) и для примеров
/// в карточках из реальных фраз серии.
public enum SubtitleParser {

    public static func parse(_ raw: String) throws -> SubtitleTrack {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SubtitleParseError.empty
        }

        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var cues: [SubtitleCue] = []
        var index = 0

        // Блоки разделены пустой строкой — одинаково в SRT и WebVTT.
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }

            guard let timingLine = lines.firstIndex(where: { $0.contains("-->") }) else {
                continue  // заголовок WEBVTT, комментарии, мусор
            }
            guard let (start, end) = parseTiming(lines[timingLine]) else { continue }

            let text = lines[(timingLine + 1)...]
                .map(clean)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !text.isEmpty else { continue }

            index += 1
            cues.append(SubtitleCue(index: index, start: start, end: end, text: text))
        }

        guard !cues.isEmpty else { throw SubtitleParseError.noCues }
        return SubtitleTrack(cues: cues)
    }

    /// `00:01:23,456 --> 00:01:25,000` или с точкой, как в WebVTT.
    static func parseTiming(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        guard let start = parseTimestamp(parts[0]),
              let end = parseTimestamp(parts[1]) else { return nil }
        return (start, end)
    }

    static func parseTimestamp(_ raw: String) -> TimeInterval? {
        // Отрезаем настройки позиции WebVTT вида «align:start position:10%».
        let token = raw
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ")
            .first?
            .replacingOccurrences(of: ",", with: ".") ?? ""
        guard !token.isEmpty else { return nil }

        let components = token.components(separatedBy: ":")
        guard components.count == 2 || components.count == 3 else { return nil }

        var seconds: TimeInterval = 0
        for component in components.dropLast() {
            guard let value = Double(component) else { return nil }
            seconds = seconds * 60 + value
        }
        guard let last = Double(components[components.count - 1]) else { return nil }
        return seconds * 60 + last
    }

    /// Убирает разметку, которую ни модели, ни человеку читать не нужно.
    static func clean(_ line: String) -> String {
        var result = line

        // Теги вида <i>, </b>, <font color="…"> и позиционирование {\an8}.
        result = result.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "\\{[^}]*\\}", with: "", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespaces)
    }
}
