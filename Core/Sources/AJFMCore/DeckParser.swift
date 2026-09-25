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
            return tr("Не похоже на JSON: \(detail)",
                      "Não parece JSON: \(detail)",
                      "Doesn't look like JSON: \(detail)")
        case .wrongFormat(let found):
            return tr("Чужой формат файла: «\(found)». Ожидается «\(DeckFile.formatID)».",
                      "Formato de ficheiro estranho: «\(found)». Esperava-se «\(DeckFile.formatID)».",
                      "Unknown file format: “\(found)”. Expected “\(DeckFile.formatID)”.")
        case .unsupportedVersion(let found, let supported):
            return tr("Версия формата \(found) новее поддерживаемой (\(supported)). Обнови приложение.",
                      "A versão do formato \(found) é mais recente do que a suportada (\(supported)). "
                        + "Atualiza a aplicação.",
                      "Format version \(found) is newer than supported (\(supported)). Update the app.")
        case .emptyDeckName:
            return tr("У набора пустое название.",
                      "O baralho não tem nome.",
                      "The deck has no name.")
        case .noNotes:
            return tr("Не нашёл в файле списка слов. Он должен называться «notes» "
                        + "(подойдут и «cards», «words») и содержать хотя бы одно слово.",
                      "Não encontrei a lista de palavras no ficheiro. Deve chamar-se «notes» "
                        + "(também servem «cards», «words») e ter pelo menos uma palavra.",
                      "Couldn't find a list of words in the file. It should be called “notes” "
                        + "(“cards” or “words” work too) and contain at least one word.")
        case .missingField(let index, let field):
            return tr("В слове №\(index + 1) не заполнено поле «\(field)».",
                      "Na palavra n.º \(index + 1) falta o campo «\(field)».",
                      "Word #\(index + 1) is missing the “\(field)” field.")
        }
    }
}

public enum DeckParser {
    public static func parse(data: Data) throws -> DeckFile {
        // Сначала приводим к формату: модель могла назвать поля по-своему.
        let canonical = try DeckNormalizer.normalize(data: data)
        let file: DeckFile
        do {
            file = try JSONDecoder().decode(DeckFile.self, from: canonical)
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
            throw DeckParseError.notJSON(tr("не удалось прочитать текст как UTF-8",
                                            "não foi possível ler o texto como UTF-8",
                                            "couldn't read the text as UTF-8"))
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
            return tr("нет обязательного поля «\(key.stringValue)»",
                      "falta o campo obrigatório «\(key.stringValue)»",
                      "the required field “\(key.stringValue)” is missing")
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: " → ")
            return path.isEmpty
                ? context.debugDescription
                : tr("поле «\(path)» заполнено неверно",
                     "o campo «\(path)» está mal preenchido",
                     "the “\(path)” field has a wrong value")
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
