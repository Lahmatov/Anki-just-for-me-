import Foundation

/// Урок на карте уроков.
public struct LessonStep: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var createdAt: Date
    public var totalWords: Int
    /// Сколько слов уже начато (хотя бы одна карточка вышла из новых).
    public var startedWords: Int
    /// Лучший результат мини-теста, 0…1; nil — теста ещё не было.
    public var bestQuiz: Double?

    public init(id: String, name: String, createdAt: Date, totalWords: Int, startedWords: Int,
                bestQuiz: Double? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.totalWords = max(totalWords, 0)
        self.startedWords = min(max(startedWords, 0), max(totalWords, 0))
        self.bestQuiz = bestQuiz.map { min(max($0, 0), 1) }
    }

    public var wordsDone: Bool { totalWords > 0 && startedWords >= totalWords }
    public var quizPassed: Bool { bestQuiz.map(LessonQuiz.passed) ?? false }

    /// Урок пройден, когда начаты все слова и сдан мини-тест: оба проверяемы,
    /// в отличие от «прочитал». Одно без другого — ещё в пути.
    public var isDone: Bool { wordsDone && quizPassed }

    /// Заполнение кружка: слова — до 70%, тест — оставшиеся 30%.
    public var fraction: Double {
        guard totalWords > 0 else { return 0 }
        let words = Double(startedWords) / Double(totalWords)
        return words * 0.7 + (quizPassed ? 0.3 : 0)
    }
}

/// Карта уроков: шаг — урок, в порядке, в котором их добавляли.
public struct LessonPath: Equatable, Sendable {
    public var steps: [LessonStep]

    public init(steps: [LessonStep]) {
        var seen = Set<String>()
        self.steps = steps
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) }
    }

    public var doneCount: Int { steps.filter(\.isDone).count }
    public var total: Int { steps.count }

    /// Где фишка: первый непройденный урок; nil — всё пройдено или уроков нет.
    public var current: LessonStep? { steps.first { !$0.isDone } }
}
