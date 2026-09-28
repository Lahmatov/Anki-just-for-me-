import Foundation

/// Грамматическая часть теста уровня.
///
/// Словарь говорит, сколько слов человек узнаёт, но не то, умеет ли он
/// их связать: «знаю 7 тысяч слов» и «путаю Past Simple с Present
/// Perfect» встречаются вместе постоянно. Поэтому к словарю добавлены
/// вопросы с выбором ответа — по три на каждую ступень от A1 до C2.
///
/// Предложения — американский английский, по одному правильному варианту;
/// спорные случаи (британское shall, needn't) сознательно не берутся.
public enum GrammarTest {

    public struct Question: Equatable, Hashable, Sendable, Identifiable {
        public var id: Int
        public var level: CEFRLevel
        /// Предложение с пропуском «___».
        public var prompt: String
        /// Первый вариант — правильный; на экран они идут перемешанными.
        public var options: [String]

        public var answer: String { options[0] }
    }

    /// Сколько вопросов на ступень и сколько из них нужно решить, чтобы
    /// ступень засчиталась. Два из трёх при четырёх вариантах случайно
    /// набирается примерно в одном случае из шести.
    public static let perLevel = 3
    public static let passMark = 2
    /// Доля верных ответов на всех ступенях до текущей включительно:
    /// одна случайная ошибка внизу не должна обрушивать итог.
    public static let cumulativeMark = 0.6

    public static let questions: [Question] = {
        let raw: [(CEFRLevel, String, [String])] = [
            (.a1, "She ___ from Brazil.", ["is", "are", "am", "be"]),
            (.a1, "I ___ like coffee.", ["don't", "doesn't", "not", "no"]),
            (.a1, "There ___ two cats in the kitchen.", ["are", "is", "be", "has"]),

            (.a2, "I ___ to the movies last night.", ["went", "go", "have gone", "was go"]),
            (.a2, "This show is ___ than the last one.",
             ["funnier", "more funny", "funniest", "the funnier"]),
            (.a2, "We ___ dinner when the phone rang.",
             ["were having", "had", "have", "are having"]),

            (.b1, "I've lived here ___ 2019.", ["since", "for", "from", "during"]),
            (.b1, "If it rains tomorrow, we ___ at home.",
             ["will stay", "would stay", "stayed", "would have stayed"]),
            (.b1, "The movie ___ by millions of people.",
             ["was watched", "watched", "has watching", "was watching"]),

            (.b2, "If I ___ you, I'd talk to her.", ["were", "am", "would be", "have been"]),
            (.b2, "She ___ have left already — her car is gone.",
             ["must", "can't", "shouldn't", "won't"]),
            (.b2, "I'm not used to ___ up so early.", ["getting", "get", "got", "have got"]),

            (.c1, "___ had I sat down when the fire alarm went off.",
             ["Hardly", "No sooner", "Rarely", "Seldom"]),
            (.c1, "If he had taken the job, he ___ in New York now.",
             ["would be living", "would have lived", "will live", "had lived"]),
            (.c1, "It's high time we ___ a decision.",
             ["made", "make", "will make", "are making"]),

            (.c2, "Little ___ that the whole thing had been staged.",
             ["did they know", "they knew", "they did know", "knew they"]),
            (.c2, "The committee insisted that he ___ present at the hearing.",
             ["be", "is", "will be", "has been"]),
            (.c2, "___ the weather been better, the launch would have gone ahead.",
             ["Had", "If", "Should", "Were"]),
        ]
        return raw.enumerated().map { index, item in
            Question(id: index, level: item.0, prompt: item.1, options: item.2)
        }
    }()

    /// Варианты вперемешку, но воспроизводимо: иначе правильный ответ
    /// всегда стоял бы первым.
    public static func shuffledOptions(of question: Question, seed: UInt64) -> [String] {
        var generator = SplitMix64(seed: seed &+ UInt64(question.id) &* 0x9E37_79B9)
        return question.options.shuffled(using: &generator)
    }

    /// Грамматическая ступень по ответам (номер вопроса → верно ли).
    ///
    /// Засчитывается самая высокая ступень, на которой решено не меньше
    /// `passMark` из `perLevel` и при этом по всем ступеням до неё включительно
    /// верных не меньше `cumulativeMark`. Ниже A1 шкалы нет — A1 и остаётся.
    public static func level(answers: [Int: Bool]) -> CEFRLevel {
        var best = CEFRLevel.a1
        var correctSoFar = 0
        var askedSoFar = 0
        for level in CEFRLevel.allCases {
            let ids = questions.filter { $0.level == level }.map(\.id)
            let correct = ids.filter { answers[$0] == true }.count
            correctSoFar += correct
            askedSoFar += ids.count
            let cumulative = askedSoFar > 0 ? Double(correctSoFar) / Double(askedSoFar) : 0
            if correct >= passMark, cumulative >= cumulativeMark {
                best = level
            }
        }
        return best
    }

    /// Итоговый уровень по словарю и грамматике — среднее, округлённое вниз.
    /// Вниз, потому что слова подбираются на ступень выше итога: переоценка
    /// дала бы наборы, в которых половина незнакома, а это бросают.
    public static func combined(vocabulary: CEFRLevel, grammar: CEFRLevel?) -> CEFRLevel {
        guard let grammar else { return vocabulary }
        let all = CEFRLevel.allCases
        let a = all.firstIndex(of: vocabulary) ?? 0
        let b = all.firstIndex(of: grammar) ?? 0
        return all[(a + b) / 2]
    }
}
