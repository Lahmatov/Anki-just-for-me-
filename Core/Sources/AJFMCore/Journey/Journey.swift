import Foundation

/// Остановка на карте путешествия.
public struct JourneyStop: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case start
        case step
        /// Каждая пятая остановка — сундук: заметная веха и праздник.
        case chest
        case finish
    }

    public var index: Int
    /// Сколько очков пути нужно, чтобы дойти сюда с начала круга.
    public var threshold: Int
    public var kind: Kind
    /// Место из сериала и сам сериал — названия собственные, не переводятся.
    public var place: String
    public var show: String

    public var id: Int { index }

    public init(index: Int, threshold: Int, kind: Kind, place: String, show: String) {
        self.index = index
        self.threshold = threshold
        self.kind = kind
        self.place = place
        self.show = show
    }
}

/// Где сейчас фишка.
public struct JourneyPosition: Equatable, Sendable {
    /// Сколько кругов пройдено целиком (0 — первый круг).
    public var lap: Int
    /// Остановка на текущем круге, до которой уже дошли.
    public var stopIndex: Int
    /// Очки, набранные после этой остановки, и длина пути до следующей.
    public var pointsIntoLeg: Int
    public var legLength: Int
    /// Сколько остановок пройдено за всё время, считая все круги. По этому
    /// числу решается, что праздновать.
    public var reachedStops: Int

    public var pointsToNext: Int { max(legLength - pointsIntoLeg, 0) }

    public var fraction: Double {
        legLength > 0 ? min(max(Double(pointsIntoLeg) / Double(legLength), 0), 1) : 0
    }

    public init(lap: Int, stopIndex: Int, pointsIntoLeg: Int, legLength: Int, reachedStops: Int) {
        self.lap = lap
        self.stopIndex = stopIndex
        self.pointsIntoLeg = pointsIntoLeg
        self.legLength = legLength
        self.reachedStops = reachedStops
    }
}

/// Карта-путешествие по Америке из сериалов: фишка с Мончиком идёт от
/// остановки к остановке, как в настольной игре.
///
/// Ходит фишка не за время в приложении, а за слова: очко — за каждое
/// начатое слово и ещё одно, когда слово выучено (дожило до долгосрочной
/// памяти). Так карта растёт от учёбы, а не от того, сколько раз открыли
/// экран, и начинающий видит движение с первого дня, а не через три недели,
/// когда созреют первые слова. Решение P-53 в docs/decisions.md.
public enum Journey {

    /// Места по порядку. Первое — старт, последнее — финиш круга.
    static let places: [(place: String, show: String)] = [
        ("Monchik's Den", "Recap"),
        ("Scranton", "The Office"),
        ("Stars Hollow", "Gilmore Girls"),
        ("Hawkins", "Stranger Things"),
        ("Pawnee", "Parks and Recreation"),
        ("Central Perk", "Friends"),
        ("Greendale", "Community"),
        ("Twin Peaks", "Twin Peaks"),
        ("Riverdale", "Riverdale"),
        ("The Nine-Nine", "Brooklyn Nine-Nine"),
        ("Albuquerque", "Breaking Bad"),
        ("Springfield", "The Simpsons"),
        ("Sunnydale", "Buffy the Vampire Slayer"),
        ("Quahog", "Family Guy"),
        ("Mystic Falls", "The Vampire Diaries"),
        ("Seattle Grace", "Grey's Anatomy"),
        ("Dillon", "Friday Night Lights"),
        ("Bluebell", "Hart of Dixie"),
        ("Newport Beach", "The O.C."),
        ("Rosewood", "Pretty Little Liars"),
        ("Madison Avenue", "Mad Men"),
        ("Tree Hill", "One Tree Hill"),
        ("Wisteria Lane", "Desperate Housewives"),
        ("Bon Temps", "True Blood"),
        ("Capeside", "Dawson's Creek"),
        ("Litchfield", "Orange Is the New Black"),
        ("Mayberry", "The Andy Griffith Show"),
        ("Cicely", "Northern Exposure"),
        ("Palo Alto", "Silicon Valley"),
        ("Hollywood", "Entourage"),
    ]

    /// Шаг до остановки `index`. Первые пять — по 5 очков, чтобы первая
    /// же сессия сдвинула фишку; дальше каждые пять остановок шаг растёт
    /// на 5: без роста середина пути пролеталась бы, а конец тянулся бы
    /// так же быстро, и вехи перестали бы что-то значить.
    public static func legLength(to index: Int) -> Int {
        guard index > 0 else { return 0 }
        return 5 * ((index - 1) / 5 + 1)
    }

    public static let stops: [JourneyStop] = {
        var threshold = 0
        return places.enumerated().map { index, entry in
            threshold += legLength(to: index)
            let kind: JourneyStop.Kind
            if index == 0 {
                kind = .start
            } else if index == places.count - 1 {
                kind = .finish
            } else if index % 5 == 0 {
                kind = .chest
            } else {
                kind = .step
            }
            return JourneyStop(index: index, threshold: threshold, kind: kind,
                               place: entry.place, show: entry.show)
        }
    }()

    /// Очков на один круг — порог финиша.
    public static var lapLength: Int { stops.last?.threshold ?? 0 }

    /// Очки пути. Выученных не может быть больше начатых — если база
    /// говорит иначе, лишнее не засчитывается, а отрицательное считается нулём.
    public static func points(startedWords: Int, matureWords: Int) -> Int {
        let started = max(startedWords, 0)
        return started + min(max(matureWords, 0), started)
    }

    /// Положение фишки. После финиша начинается новый круг с того же старта.
    public static func position(points rawPoints: Int) -> JourneyPosition {
        let points = max(rawPoints, 0)
        let perLap = lapLength
        let stopsPerLap = stops.count - 1
        guard perLap > 0, stopsPerLap > 0 else {
            return JourneyPosition(lap: 0, stopIndex: 0, pointsIntoLeg: 0, legLength: 0, reachedStops: 0)
        }
        let lap = points / perLap
        let within = points % perLap
        let index = stops.lastIndex { $0.threshold <= within } ?? 0
        let next = index + 1 < stops.count ? stops[index + 1].threshold : perLap
        return JourneyPosition(
            lap: lap, stopIndex: index,
            pointsIntoLeg: within - stops[index].threshold,
            legLength: next - stops[index].threshold,
            reachedStops: lap * stopsPerLap + index)
    }

    /// Веха, которую стоит отпраздновать: последний сундук или финиш,
    /// пройденный с прошлого праздника, или nil.
    ///
    /// Праздник на каждой клетке перестал бы быть праздником уже на
    /// второй день — поэтому только сундуки и финиш; обычные клетки видны
    /// на карте ходом фишки. `celebrated` меньше нуля — праздновать ещё не
    /// начинали (первый запуск после обновления): иначе человек с полугодом
    /// учёбы получил бы салют за сундук, открытый давно. Откат (слова
    /// забылись) праздника не даёт, и повторного за ту же веху тоже.
    public static func stopToCelebrate(celebrated: Int, reached: Int) -> Int? {
        guard celebrated >= 0, reached > celebrated else { return nil }
        return ((celebrated + 1)...reached).last { isMilestone(stop(reached: $0)) }
    }

    public static func isMilestone(_ stop: JourneyStop) -> Bool {
        stop.kind == .chest || stop.kind == .finish
    }

    /// Остановка по сквозному номеру (с учётом кругов).
    public static func stop(reached: Int) -> JourneyStop {
        let stopsPerLap = max(stops.count - 1, 1)
        let index = max(reached, 0) % stopsPerLap
        // Сквозной номер, кратный длине круга, — это финиш, а не старт
        // следующего круга: праздновать нужно именно его.
        if reached > 0, index == 0 { return stops[stops.count - 1] }
        return stops[index]
    }
}
