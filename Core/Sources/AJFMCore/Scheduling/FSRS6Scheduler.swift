import Foundation

/// FSRS-6 — алгоритм по умолчанию.
///
/// Порт эталонной реализации py-fsrs (open-spaced-repetition), сверенный с ней
/// тестовыми векторами — см. `FSRS6ReferenceTests`. Любое расхождение с эталоном
/// считается ошибкой здесь, а не улучшением: планирование повторений невозможно
/// проверить на глаз, поэтому единственная защита — побитовое совпадение.
///
/// Модель памяти держит три величины:
/// - **устойчивость** (stability) — через сколько дней вероятность вспомнить упадёт до 90%;
/// - **сложность** (difficulty, 1...10) — насколько тяжело даётся именно эта карточка;
/// - **извлекаемость** (retrievability) — вероятность вспомнить прямо сейчас.
public struct FSRS6Scheduler: Scheduler {
    public let id: SchedulerID = .fsrs6

    /// Обучены примерно на 700 млн повторений 10 тысяч пользователей Anki.
    public static let defaultParameters: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722,
        0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425,
        0.0912, 0.0658, 0.1542,
    ]

    public static let stabilityMin: Double = 0.001
    public static let difficultyMin: Double = 1
    public static let difficultyMax: Double = 10

    public var parameters: [Double]
    /// Доля карточек, которую хочется помнить на момент повторения. 0.9 — разумный
    /// дефолт: выше — заметно больше повторений ради небольшого выигрыша.
    public var desiredRetention: Double
    public var learningSteps: [TimeInterval]
    public var relearningSteps: [TimeInterval]
    public var maximumInterval: Int
    /// Разброс интервалов, чтобы карточки, выученные в один день, не слипались
    /// в одну огромную очередь через месяц. В тестах выключается.
    public var enableFuzzing: Bool

    public init(
        parameters: [Double] = FSRS6Scheduler.defaultParameters,
        desiredRetention: Double = 0.9,
        learningSteps: [TimeInterval] = [60, 600],
        relearningSteps: [TimeInterval] = [600],
        maximumInterval: Int = 36_500,
        enableFuzzing: Bool = true
    ) {
        self.parameters = parameters.count == FSRS6Scheduler.defaultParameters.count
            ? parameters
            : FSRS6Scheduler.defaultParameters
        self.desiredRetention = desiredRetention
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.maximumInterval = maximumInterval
        self.enableFuzzing = enableFuzzing
    }

    private var decay: Double { -parameters[20] }
    private var factor: Double { pow(0.9, 1 / decay) - 1 }

    // MARK: - Извлекаемость

    /// Вероятность вспомнить карточку прямо сейчас, 0...1.
    public func retrievability(_ state: ReviewState, now: Date) -> Double {
        guard let lastReview = state.lastReview, let stability = state.stability else {
            return 0
        }
        let days = Double(max(0, elapsedDays(from: lastReview, to: now)))
        return pow(1 + factor * days / stability, decay)
    }

    // MARK: - Повторение

    public func review(_ state: ReviewState, grade: Grade, now: Date) -> ReviewState {
        var card = state
        let daysSinceLastReview = card.lastReview.map { elapsedDays(from: $0, to: now) }
        let nextInterval: TimeInterval

        switch card.state {
        case .new, .learning:
            updateMemory(&card, grade: grade, now: now, daysSince: daysSinceLastReview)
            nextInterval = advanceThroughSteps(
                &card, grade: grade, steps: learningSteps, fallbackState: .learning)

        case .review:
            // В фазе повторения сложность обновляется всегда, а устойчивость —
            // по-разному для повтора в тот же день и для отложенного.
            if let days = daysSinceLastReview, days < 1, let stability = card.stability {
                card.stability = shortTermStability(stability: stability, grade: grade)
            } else if let stability = card.stability, let difficulty = card.difficulty {
                card.stability = nextStability(
                    difficulty: difficulty,
                    stability: stability,
                    retrievability: retrievability(state, now: now),
                    grade: grade)
            }
            if let difficulty = card.difficulty {
                card.difficulty = nextDifficulty(difficulty: difficulty, grade: grade)
            }

            if grade == .again {
                if relearningSteps.isEmpty {
                    nextInterval = reviewInterval(card)
                } else {
                    card.state = .relearning
                    card.step = 0
                    nextInterval = relearningSteps[0]
                }
            } else {
                nextInterval = reviewInterval(card)
            }

        case .relearning:
            updateMemory(&card, grade: grade, now: now, daysSince: daysSinceLastReview)
            nextInterval = advanceThroughSteps(
                &card, grade: grade, steps: relearningSteps, fallbackState: .relearning)
        }

        var interval = nextInterval
        if enableFuzzing, card.state == .review {
            interval = fuzzed(interval)
        }

        card.due = now.addingTimeInterval(interval)
        card.lastReview = now
        card.intervalDays = interval / 86_400
        card.reps += 1
        if grade == .again, state.state == .review { card.lapses += 1 }

        return card
    }

    /// Обновление устойчивости и сложности — общее для фаз заучивания и переучивания.
    private func updateMemory(
        _ card: inout ReviewState, grade: Grade, now: Date, daysSince: Int?
    ) {
        guard let stability = card.stability, let difficulty = card.difficulty else {
            // Первый в жизни показ карточки.
            card.stability = initialStability(grade: grade)
            card.difficulty = initialDifficulty(grade: grade, clamp: true)
            return
        }

        if let days = daysSince, days < 1 {
            card.stability = shortTermStability(stability: stability, grade: grade)
        } else {
            card.stability = nextStability(
                difficulty: difficulty,
                stability: stability,
                retrievability: retrievability(card, now: now),
                grade: grade)
        }
        card.difficulty = nextDifficulty(difficulty: difficulty, grade: grade)
    }

    /// Продвижение по шагам заучивания или переучивания.
    private func advanceThroughSteps(
        _ card: inout ReviewState,
        grade: Grade,
        steps: [TimeInterval],
        fallbackState: LearningState
    ) -> TimeInterval {
        let currentStep = card.step ?? 0

        // Шагов нет вовсе, либо карточка застряла на шаге из более длинной
        // прежней настройки — выпускаем её в обычное повторение.
        if steps.isEmpty || (currentStep >= steps.count && grade != .again) {
            card.state = .review
            card.step = nil
            return reviewInterval(card)
        }

        switch grade {
        case .again:
            card.state = fallbackState
            card.step = 0
            return steps[0]

        case .hard:
            card.state = fallbackState
            card.step = currentStep
            if currentStep == 0 && steps.count == 1 {
                return steps[0] * 1.5
            } else if currentStep == 0 && steps.count >= 2 {
                return (steps[0] + steps[1]) / 2
            }
            return steps[currentStep]

        case .good:
            if currentStep + 1 == steps.count {
                card.state = .review
                card.step = nil
                return reviewInterval(card)
            }
            card.state = fallbackState
            card.step = currentStep + 1
            return steps[currentStep + 1]

        case .easy:
            card.state = .review
            card.step = nil
            return reviewInterval(card)
        }
    }

    private func reviewInterval(_ card: ReviewState) -> TimeInterval {
        Double(nextIntervalDays(stability: card.stability ?? Self.stabilityMin)) * 86_400
    }

    // MARK: - Формулы модели

    private func clampStability(_ value: Double) -> Double {
        max(value, Self.stabilityMin)
    }

    private func clampDifficulty(_ value: Double) -> Double {
        min(max(value, Self.difficultyMin), Self.difficultyMax)
    }

    func initialStability(grade: Grade) -> Double {
        clampStability(parameters[grade.rawValue - 1])
    }

    func initialDifficulty(grade: Grade, clamp: Bool) -> Double {
        let value = parameters[4] - exp(parameters[5] * Double(grade.rawValue - 1)) + 1
        return clamp ? clampDifficulty(value) : value
    }

    func nextIntervalDays(stability: Double) -> Int {
        let raw = (stability / factor) * (pow(desiredRetention, 1 / decay) - 1)
        // Эталон округляет к ближайшему чётному (так работает round в Python) —
        // при половинных значениях обычное округление дало бы расхождение.
        let rounded = Int(raw.rounded(.toNearestOrEven))
        return min(max(rounded, 1), maximumInterval)
    }

    func shortTermStability(stability: Double, grade: Grade) -> Double {
        var increase = exp(parameters[17] * (Double(grade.rawValue) - 3 + parameters[18]))
            * pow(stability, -parameters[19])
        if grade != .again {
            increase = max(increase, 1)
        }
        return clampStability(stability * increase)
    }

    func nextDifficulty(difficulty: Double, grade: Grade) -> Double {
        let deltaDifficulty = -(parameters[6] * (Double(grade.rawValue) - 3))
        // Линейное затухание: чем сложнее карточка, тем меньше её двигают оценки.
        let damped = difficulty + (10 - difficulty) * deltaDifficulty / 9
        // Возврат к среднему тянет сложность к той, что дала бы оценка «Легко».
        let target = initialDifficulty(grade: .easy, clamp: false)
        return clampDifficulty(parameters[7] * target + (1 - parameters[7]) * damped)
    }

    func nextStability(
        difficulty: Double, stability: Double, retrievability: Double, grade: Grade
    ) -> Double {
        let value = grade == .again
            ? forgetStability(
                difficulty: difficulty, stability: stability, retrievability: retrievability)
            : recallStability(
                difficulty: difficulty, stability: stability,
                retrievability: retrievability, grade: grade)
        return clampStability(value)
    }

    func forgetStability(
        difficulty: Double, stability: Double, retrievability: Double
    ) -> Double {
        let longTerm = parameters[11]
            * pow(difficulty, -parameters[12])
            * (pow(stability + 1, parameters[13]) - 1)
            * exp((1 - retrievability) * parameters[14])
        let shortTerm = stability / exp(parameters[17] * parameters[18])
        return min(longTerm, shortTerm)
    }

    func recallStability(
        difficulty: Double, stability: Double, retrievability: Double, grade: Grade
    ) -> Double {
        let hardPenalty = grade == .hard ? parameters[15] : 1
        let easyBonus = grade == .easy ? parameters[16] : 1
        return stability * (
            1 + exp(parameters[8])
                * (11 - difficulty)
                * pow(stability, -parameters[9])
                * (exp((1 - retrievability) * parameters[10]) - 1)
                * hardPenalty
                * easyBonus
        )
    }

    // MARK: - Разброс интервалов

    private static let fuzzRanges: [(start: Double, end: Double, factor: Double)] = [
        (2.5, 7, 0.15),
        (7, 20, 0.1),
        (20, .infinity, 0.05),
    ]

    private func fuzzed(_ interval: TimeInterval) -> TimeInterval {
        let days = floor(interval / 86_400)
        guard days >= 2.5 else { return interval }

        var delta = 1.0
        for range in Self.fuzzRanges {
            delta += range.factor * max(min(days, range.end) - range.start, 0)
        }

        var minDays = Int((days - delta).rounded(.toNearestOrEven))
        var maxDays = Int((days + delta).rounded(.toNearestOrEven))
        minDays = max(2, minDays)
        maxDays = min(maxDays, maximumInterval)
        minDays = min(minDays, maxDays)

        return Double(Int.random(in: minDays...maxDays)) * 86_400
    }
}
