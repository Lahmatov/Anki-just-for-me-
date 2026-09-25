import Foundation

/// Приводит «почти правильный» набор к формату `ajfm-deck`.
///
/// Набор почти всегда пишет языковая модель, и она не обязана помнить формат
/// дословно: назовёт список `cards` вместо `notes`, слово — `word` вместо
/// `term`, обернёт JSON в markdown или вернёт голый массив. Отказывать в
/// таком случае — значит заставлять человека идти обратно в чат ради
/// переименования одного поля. Поэтому поля узнаются по смыслу, а строгая
/// проверка содержимого (пустые слова, чужой формат) остаётся за `DeckParser`.
public enum DeckNormalizer {

    /// Название набора, если в файле его нет вовсе.
    public static var fallbackDeckName: String {
        tr("Новый набор", "Novo baralho", "New deck")
    }

    public static func normalize(data: Data) throws -> Data {
        let object = try jsonObject(from: data)
        let canonical = try canonicalize(object)
        do {
            return try JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys])
        } catch {
            throw DeckParseError.notJSON(error.localizedDescription)
        }
    }

    // MARK: - Извлечение JSON

    /// JSON из текста: снимает BOM, markdown-ограды и фразы вокруг.
    static func jsonObject(from data: Data) throws -> Any {
        if let direct = try? JSONSerialization.jsonObject(with: data), isContainer(direct) {
            return direct
        }
        guard var text = String(data: data, encoding: .utf8) else {
            throw DeckParseError.notJSON(tr("не удалось прочитать текст как UTF-8",
                                            "não foi possível ler o texto como UTF-8",
                                            "couldn't read the text as UTF-8"))
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        for candidate in candidates(in: text) {
            if let object = try? JSONSerialization.jsonObject(with: Data(candidate.utf8)),
               isContainer(object) {
                return object
            }
        }
        throw DeckParseError.notJSON(tr("в тексте не нашлось JSON-объекта",
                                        "não há nenhum objeto JSON no texto",
                                        "there's no JSON object in the text"))
    }

    private static func isContainer(_ object: Any) -> Bool {
        object is [String: Any] || object is [Any]
    }

    /// Варианты вырезки: содержимое markdown-блока, затем от первой скобки
    /// до последней — сначала фигурной, потом квадратной.
    private static func candidates(in text: String) -> [String] {
        var result: [String] = []
        if let fenced = fencedBlock(in: text) { result.append(fenced) }
        for (open, close) in [("{", "}"), ("[", "]")] {
            if let start = text.firstIndex(of: Character(open)),
               let end = text.lastIndex(of: Character(close)),
               start < end {
                result.append(String(text[start...end]))
            }
        }
        return result
    }

    private static func fencedBlock(in text: String) -> String? {
        guard let open = text.range(of: "```") else { return nil }
        // Пропускаем язык после ограды: ```json
        guard let lineEnd = text[open.upperBound...].firstIndex(of: "\n") else { return nil }
        let body = text[text.index(after: lineEnd)...]
        guard let close = body.range(of: "```") else { return nil }
        return String(body[..<close.lowerBound])
    }

    // MARK: - Приведение к формату

    private static let notesKeys = [
        "notes", "cards", "words", "items", "vocabulary", "flashcards",
        "entries", "terms", "list",
    ]
    private static let nameKeys = ["name", "title", "deckname", "deck"]

    static func canonicalize(_ object: Any) throws -> [String: Any] {
        if let array = object as? [Any] {
            return try build(meta: [:], root: [:], notes: array)
        }
        guard let root = object as? [String: Any] else {
            throw DeckParseError.notJSON(tr("ожидался объект или список",
                                            "esperava-se um objeto ou uma lista",
                                            "expected an object or a list"))
        }

        if let format = string(root["format"]), format != DeckFile.formatID {
            throw DeckParseError.wrongFormat(found: format)
        }

        let deck = root["deck"] as? [String: Any] ?? [:]
        if let notes = findNotes(in: root) ?? findNotes(in: deck) {
            return try build(meta: deck, root: root, notes: notes)
        }

        // Обёртка из одного ключа: {"deck_1": {...}} или {"ajfm-deck": {...}}.
        if root.count == 1, let inner = root.values.first as? [String: Any],
           findNotes(in: inner) != nil {
            return try canonicalize(inner)
        }
        throw DeckParseError.noNotes
    }

    private static func findNotes(in dict: [String: Any]) -> [Any]? {
        let keys = normalizedKeys(dict)
        for key in notesKeys {
            if let array = keys[key] as? [Any] { return array }
        }
        return nil
    }

    private static func build(
        meta: [String: Any], root: [String: Any], notes: [Any]
    ) throws -> [String: Any] {
        let metaKeys = normalizedKeys(meta)
        let rootKeys = normalizedKeys(root)
        func field(_ names: String...) -> Any? {
            for name in names {
                if let value = metaKeys[name] { return value }
            }
            for name in names {
                if let value = rootKeys[name], !(value is [String: Any]) { return value }
            }
            return nil
        }

        var deck: [String: Any] = [:]
        let name = nameKeys.lazy.compactMap { string(field($0)) }.first { !$0.isEmpty }
        deck["name"] = name ?? fallbackDeckName
        if let folder = string(field("folder", "path", "category")) { deck["folder"] = folder }
        if let language = string(field("language", "lang")) { deck["language"] = language }
        if let source = string(field("source", "episode", "show")) { deck["source"] = source }
        if let scheduler = string(field("scheduler", "algorithm")) {
            deck["scheduler"] = scheduler.lowercased()
        }
        if let types = stringList(field("cardtypes")) { deck["cardTypes"] = types }

        guard !notes.isEmpty else { throw DeckParseError.noNotes }

        return [
            "format": DeckFile.formatID,
            "version": (rootKeys["version"] as? Int) ?? DeckFile.supportedVersion,
            "deck": deck,
            "notes": notes.map(canonicalNote),
        ]
    }

    // MARK: - Слово

    private static let noteFields: [(target: String, aliases: [String])] = [
        ("term", ["term", "word", "front", "english", "en", "expression", "phrase",
                  "headword", "lemma", "question"]),
        ("translation", ["translation", "translations", "back", "meaning", "russian", "ru",
                         "portuguese", "pt", "answer", "definition"]),
        ("ipa", ["ipa", "transcription", "pronunciation", "phonetic", "phonetics"]),
        ("partOfSpeech", ["partofspeech", "pos", "wordclass"]),
        ("example", ["example", "examples", "sentence", "context", "usage", "quote",
                     "examplesentence"]),
        ("exampleTranslation", ["exampletranslation", "sentencetranslation",
                                "translationofexample", "exampleru"]),
        ("cloze", ["cloze", "gap", "fillintheblank"]),
        ("note", ["note", "notes", "comment", "hint", "tip", "usagenote", "remark"]),
        ("difficulty", ["difficulty", "level"]),
        ("audio", ["audio", "audiourl"]),
    ]

    private static func canonicalNote(_ raw: Any) -> [String: Any] {
        if let line = raw as? String { return noteFromLine(line) }
        guard let dict = raw as? [String: Any] else { return [:] }

        let keys = normalizedKeys(dict)
        var note: [String: Any] = [:]
        for (target, aliases) in noteFields {
            for alias in aliases {
                guard let value = keys[alias] else { continue }
                // Список переводов склеиваем: «рычаг, влияние». Из списка
                // примеров берём первый — склеенные фразы читались бы как одна.
                let list = stringList(value)
                let joined = target == "example" ? list?.first : list?.joined(separator: ", ")
                if let text = string(value) ?? joined, !text.isEmpty {
                    note[target] = text
                    break
                }
            }
        }
        if let pos = note["partOfSpeech"] as? String {
            note["partOfSpeech"] = pos.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
        }
        if let difficulty = note["difficulty"] as? String {
            note["difficulty"] = difficulty.lowercased()
        }
        if let synonyms = stringList(keys["synonyms"]) { note["synonyms"] = synonyms }
        if let tags = stringList(keys["tags"]) { note["tags"] = tags }

        // Поля обязательны при разборе — пустая строка даст понятную ошибку
        // «в слове №N не заполнено поле», а не невнятное «нет ключа».
        note["term"] = note["term"] ?? ""
        note["translation"] = note["translation"] ?? ""
        return note
    }

    /// Строка вида «leverage — рычаг, влияние».
    private static func noteFromLine(_ line: String) -> [String: Any] {
        for separator in [" — ", " – ", " - ", "\t", ": ", " = "] {
            if let range = line.range(of: separator) {
                return [
                    "term": line[..<range.lowerBound].trimmingCharacters(in: .whitespaces),
                    "translation": line[range.upperBound...].trimmingCharacters(in: .whitespaces),
                ]
            }
        }
        return ["term": line.trimmingCharacters(in: .whitespaces), "translation": ""]
    }

    // MARK: - Мелочи

    /// Ключи без регистра, подчёркиваний, дефисов и пробелов:
    /// `part_of_speech`, `PartOfSpeech` и `part-of-speech` — одно и то же.
    private static func normalizedKeys(_ dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
            if result[normalized] == nil { result[normalized] = value }
        }
        return result
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringList(_ value: Any?) -> [String]? {
        if let array = value as? [Any] {
            let items = array.compactMap { string($0) }
            return items.isEmpty ? nil : items
        }
        if let text = string(value) {
            let items = text.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return items.isEmpty ? nil : items
        }
        return nil
    }
}
