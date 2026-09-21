import Foundation

public enum DeckParseError: Error, Equatable, LocalizedError {
    case notJSON(String)
    case wrongFormat(found: String)
    case unsupportedVersion(found: Int, supported: Int)
    case emptyDeckName
    case noNotes
    case missingField(noteIndex: Int, field: String)

    public var errorDescription: String? {
        switch self {
        case .notJSON(let detail):
            return "Не похоже на JSON: \(detail)"
        case .wrongFormat(let found):
            return "Чужой формат файла: «\(found)». Ожидается «\(DeckFile.formatID)»."
        case .unsupportedVersion(let found, let supported):
            return "Версия формата \(found) новее поддерживаемой (\(supported)). Обнови приложение."
        case .emptyDeckName:
            return "У набора пустое название."
        case .noNotes:
            return "В наборе нет ни одного слова."
        case .missingField(let index, let field):
            return "В слове №\(index + 1) не заполнено поле «\(field)»."
        }
    }
}

public enum DeckParser {
    public static func parse(data: Data) throws -> DeckFile {
        let file: DeckFile
        do {
            file = try JSONDecoder().decode(DeckFile.self, from: data)
        } catch let error as DecodingError {
            throw DeckParseError.notJSON(describe(error))
        } catch {
            throw DeckParseError.notJSON(error.localizedDescription)
        }

        guard file.format == DeckFile.formatID else {
            throw DeckParseError.wrongFormat(found: file.format)
        }
        guard file.version <= DeckFile.supportedVersion else {
            throw DeckParseError.unsupportedVersion(
                found: file.version, supported: DeckFile.supportedVersion)
        }
        guard !file.deck.name.trimmed.isEmpty else { throw DeckParseError.emptyDeckName }
        guard !file.notes.isEmpty else { throw DeckParseError.noNotes }

        for (index, note) in file.notes.enumerated() {
            guard !note.term.trimmed.isEmpty else {
                throw DeckParseError.missingField(noteIndex: index, field: "term")
            }
            guard !note.translation.trimmed.isEmpty else {
                throw DeckParseError.missingField(noteIndex: index, field: "translation")
            }
        }

        return file
    }

    public static func parse(string: String) throws -> DeckFile {
        guard let data = string.data(using: .utf8) else {
            throw DeckParseError.notJSON("не удалось прочитать текст как UTF-8")
        }
        return try parse(data: data)
    }

    public static func encode(_ file: DeckFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return "нет обязательного поля «\(key.stringValue)»"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: " → ")
            return path.isEmpty ? context.debugDescription : "поле «\(path)» заполнено неверно"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return "\(error)"
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
