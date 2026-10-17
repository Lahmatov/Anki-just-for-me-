import Foundation

/// Проверка диктанта: фраза сравнивается по словам, а не целиком.
///
/// Целиком — бесполезно: одна пропущенная запятая или артикль, и вся
/// фраза «неверна». По словам видно, что именно не расслышано. Регистр и
/// пунктуация не считаются; потерянное ударение («esta» вместо «está») —
/// отдельная пометка, а не ошибка: на слух его не отличить, но писать надо.
public struct DictationResult: Equatable, Sendable {
    public enum Mark: String, Equatable, Sendable {
        case correct
        /// Слово верное, но без ударения или с другим знаком.
        case accent
        /// Одна буква не та — расслышано, но написано с опечаткой.
        case typo
        /// Вместо слова написано другое.
        case wrong
        case missing
        case extra
    }

    public struct Word: Equatable, Sendable {
        public var expected: String?
        public var typed: String?
        public var mark: Mark

        public init(expected: String?, typed: String?, mark: Mark) {
            self.expected = expected
            self.typed = typed
            self.mark = mark
        }
    }

    public var words: [Word]

    public init(words: [Word]) {
        self.words = words
    }

    /// Доля от 0 до 1: верное слово — целое, ударение и опечатка — половина.
    /// Лишние слова отнимают, как пропущенные: иначе выгодно писать всё подряд.
    public var score: Double {
        let expected = words.filter { $0.expected != nil }.count
        guard expected > 0 else { return 0 }
        var points = 0.0
        for word in words {
            switch word.mark {
            case .correct: points += 1
            case .accent, .typo: points += 0.5
            case .extra: points -= 0.5
            case .wrong, .missing: break
            }
        }
        return min(max(points / Double(expected), 0), 1)
    }

    public var isPerfect: Bool { !words.isEmpty && words.allSatisfy { $0.mark == .correct } }
}

public enum DictationCheck {

    public static func check(typed: String, expected: String) -> DictationResult {
        let target = tokens(expected)
        let input = tokens(typed)
        guard !target.isEmpty else { return DictationResult(words: []) }

        // Выравнивание по общей подпоследовательности слов без учёта ударений:
        // так «esta» встаёт против «está», а не уезжает в «лишние».
        let a = target.map(fold)
        let b = input.map(fold)
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var words: [DictationResult.Word] = []
        var missing: [String] = []
        var extra: [String] = []
        func flushGap() {
            // В промежутке между совпадениями ставим слова попарно: это
            // замены; остаток — пропуски или лишние.
            let pairs = min(missing.count, extra.count)
            for index in 0..<pairs {
                let close = missing[index].count >= 4
                    && AnswerChecker.editDistance(fold(missing[index]), fold(extra[index]), limit: 1) <= 1
                words.append(.init(expected: missing[index], typed: extra[index], mark: close ? .typo : .wrong))
            }
            for word in missing.dropFirst(pairs) { words.append(.init(expected: word, typed: nil, mark: .missing)) }
            for word in extra.dropFirst(pairs) { words.append(.init(expected: nil, typed: word, mark: .extra)) }
            missing.removeAll()
            extra.removeAll()
        }

        var i = 0
        var j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                flushGap()
                let exact = target[i] == input[j]
                words.append(.init(expected: target[i], typed: input[j], mark: exact ? .correct : .accent))
                i += 1
                j += 1
            } else if j < b.count, i == a.count || table[i][j + 1] >= table[i + 1][j] {
                extra.append(input[j])
                j += 1
            } else {
                missing.append(target[i])
                i += 1
            }
        }
        flushGap()
        return DictationResult(words: words)
    }

    /// Слова без пунктуации по краям, в нижнем регистре; апострофы
    /// («l'acqua», «don't») остаются частью слова.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'"))) }
            .flatMap { $0.split(separator: "—").map(String.init) }
            .filter { !$0.isEmpty }
    }

    static func fold(_ word: String) -> String {
        word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
