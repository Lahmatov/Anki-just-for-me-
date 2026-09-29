import Foundation

/// Юридические документы приложения: условия, политика, лицензии.
///
/// Тексты лежат в `docs/legal/*.md` и попадают в приложение как ресурсы:
/// в приложении ровно те же слова, что и на опубликованной странице, и
/// читаются они без сети. Здесь — выбор файла по языку, подстановка данных
/// продавца и разбор простого Markdown на блоки для экрана.
public enum LegalDocument {

    public enum Kind: String, CaseIterable, Sendable, Identifiable {
        case terms, privacy, licenses

        public var id: String { rawValue }

        /// Лицензии — английские тексты лицензий, их не переводят.
        public var isTranslated: Bool { self != .licenses }

        public var title: String {
            switch self {
            case .terms: return tr("Условия использования", "Termos de utilização", "Terms of Use")
            case .privacy: return tr("Политика конфиденциальности", "Política de privacidade",
                                     "Privacy Policy")
            case .licenses: return tr("Лицензии", "Licenças", "Licenses")
            }
        }
    }

    /// Имя ресурса без расширения: `terms.pt`, `privacy.ru`, `licenses.en`.
    public static func resourceName(_ kind: Kind, language: AppLanguage) -> String {
        "\(kind.rawValue).\(kind.isTranslated ? language.rawValue : AppLanguage.english.rawValue)"
    }

    // MARK: - Данные продавца

    /// Имя, адрес и почта продавца. Те же, что в App Store Connect для DSA:
    /// они обязаны совпадать, поэтому задаются в одном месте — Info.plist.
    public struct Seller: Equatable, Sendable {
        public var name: String
        public var address: String
        public var email: String

        public init(name: String, address: String, email: String) {
            self.name = name
            self.address = address
            self.email = email
        }

        /// Заглушка «CHANGE-ME» или пустое значение — ещё не заполнено.
        public static func isPlaceholder(_ value: String) -> Bool {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.contains("CHANGE-ME")
        }

        public var isComplete: Bool {
            ![name, address, email].contains(where: Self.isPlaceholder)
        }

        /// Почта, годная для mailto: заполнена и похожа на адрес.
        public var contactEmail: String? {
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !Self.isPlaceholder(trimmed), SupportMail.looksLikeEmail(trimmed) else { return nil }
            return trimmed
        }
    }

    /// Подстановка данных продавца вместо меток в тексте. Незаполненное
    /// остаётся меткой: пусть лучше будет видно, что забыли, чем пустое место.
    public static func fill(_ text: String, seller: Seller) -> String {
        var result = text
        for (placeholder, value) in [("CONTROLLER_NAME", seller.name),
                                     ("CONTROLLER_ADDRESS", seller.address),
                                     ("CONTACT_EMAIL", seller.email)]
        where !Seller.isPlaceholder(value) {
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        return result
    }

    // MARK: - Разбор

    public enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case numbered(Int, String)
        /// Строки таблицы, первая — заголовок.
        case table([[String]])
        case rule
    }

    /// Разбор того Markdown, что встречается в наших документах: заголовки,
    /// абзацы, списки, таблицы и разделители. Встроенная разметка (жирный,
    /// ссылки) остаётся в тексте — её рисует экран.
    public static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var table: [[String]] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }
        func flushTable() {
            guard !table.isEmpty else { return }
            blocks.append(.table(table))
            table = []
        }
        func flush() {
            flushParagraph()
            flushTable()
        }

        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let indented = raw.hasPrefix("  ") || raw.hasPrefix("\t")

            if line.isEmpty {
                flush()
                continue
            }
            if line.hasPrefix("|") {
                flushParagraph()
                let cells = tableCells(line)
                // Строка «|---|:---:|» только отделяет заголовок — в данные не идёт.
                if !cells.allSatisfy(isSeparatorCell) { table.append(cells) }
                continue
            }
            flushTable()

            if let heading = heading(line) {
                flushParagraph()
                blocks.append(heading)
            } else if line == "---" || line == "***" || line == "___" {
                flushParagraph()
                blocks.append(.rule)
            } else if let text = bulletText(line) {
                flushParagraph()
                blocks.append(.bullet(text))
            } else if let item = numberedItem(line) {
                flushParagraph()
                blocks.append(.numbered(item.number, item.text))
            } else if indented, paragraph.isEmpty, let last = blocks.last {
                // Продолжение пункта списка на следующей строке.
                switch last {
                case .bullet(let text):
                    blocks[blocks.count - 1] = .bullet(text + " " + line)
                case .numbered(let number, let text):
                    blocks[blocks.count - 1] = .numbered(number, text + " " + line)
                default:
                    paragraph.append(line)
                }
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    private static func heading(_ line: String) -> Block? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : .heading(level: hashes, text: text)
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            let text = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> (number: Int, text: String)? {
        let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty, digits.count <= 3, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        let text = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (number, text)
    }

    private static func tableCells(_ line: String) -> [String] {
        var body = Substring(line)
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|") { body = body.dropLast() }
        return body.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isSeparatorCell(_ cell: String) -> Bool {
        !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" } && cell.contains("-")
    }
}
