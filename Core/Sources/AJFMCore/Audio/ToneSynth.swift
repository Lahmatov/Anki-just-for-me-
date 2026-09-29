import Foundation

/// Нота звукового сигнала: частота, начало, длительность, громкость.
public struct Tone: Equatable, Sendable {
    public var frequency: Double
    public var start: Double
    public var duration: Double
    public var volume: Double

    public init(frequency: Double, start: Double, duration: Double, volume: Double = 0.5) {
        self.frequency = frequency
        self.start = start
        self.duration = duration
        self.volume = volume
    }

    public var end: Double { start + max(duration, 0) }
}

/// Звуки приложения — короткие и мягкие, чтобы не раздражать на сотой карточке.
///
/// Звуки синтезируются, а не лежат файлами: четыре сигнала по полсекунды —
/// это несколько нот, и файлы ради них — лишние мегабайты и лицензии.
public enum SoundCue: String, CaseIterable, Sendable {
    /// Верный ответ: два колокольчика вверх.
    case correct
    /// Неверный: один тихий низкий звук, без «ошибочного» гудка — ошибка
    /// в учёбе нормальна, за неё не ругают.
    case wrong
    /// Праздник: мажорное арпеджио и аккорд.
    case fanfare
    /// Подарок Мончику: россыпь высоких нот.
    case sparkle

    public var tones: [Tone] {
        switch self {
        case .correct:
            return [Tone(frequency: 1318.5, start: 0, duration: 0.12, volume: 0.35),     // E6
                    Tone(frequency: 1760.0, start: 0.08, duration: 0.22, volume: 0.35)]  // A6
        case .wrong:
            return [Tone(frequency: 311.1, start: 0, duration: 0.22, volume: 0.25)]      // D#4
        case .fanfare:
            let arpeggio = [523.3, 659.3, 784.0].enumerated().map { index, frequency in  // C5 E5 G5
                Tone(frequency: frequency, start: Double(index) * 0.11, duration: 0.16, volume: 0.3)
            }
            let chord = [523.3, 659.3, 784.0, 1046.5].map {                               // + C6
                Tone(frequency: $0, start: 0.36, duration: 0.6, volume: 0.18)
            }
            return arpeggio + chord
        case .sparkle:
            return [2093.0, 2637.0, 3136.0, 2637.0, 3520.0].enumerated().map { index, frequency in
                Tone(frequency: frequency, start: Double(index) * 0.06, duration: 0.14, volume: 0.2)
            }
        }
    }

    public var duration: Double {
        tones.map(\.end).max() ?? 0
    }
}

/// Синтез нот в отсчёты PCM: синус с обертоном и быстрой атакой —
/// получается «колокольчик», а не писк.
public enum ToneSynth {
    public static let sampleRate: Double = 44_100
    /// Атака: без неё начало ноты щёлкает в динамике.
    static let attack: Double = 0.005

    public static func render(_ tones: [Tone], sampleRate: Double = sampleRate) -> [Float] {
        let valid = tones.filter { $0.duration > 0 && $0.frequency > 0 && $0.start >= 0 }
        guard let end = valid.map(\.end).max(), sampleRate > 0 else { return [] }
        // До ближайшего, а не вверх: 0,1 + 0,2 секунды в двоичной дроби —
        // 0,30000000000000004, и «вверх» добавляло бы лишний отсчёт.
        let count = Int((end * sampleRate).rounded())
        var samples = [Float](repeating: 0, count: count)
        for tone in valid {
            let first = Int(tone.start * sampleRate)
            let length = Int(tone.duration * sampleRate)
            for offset in 0..<length where first + offset < count {
                let time = Double(offset) / sampleRate
                let value = sin(2 * .pi * tone.frequency * time)
                    + 0.3 * sin(2 * .pi * tone.frequency * 2 * time)
                samples[first + offset] += Float(value * tone.volume * envelope(time, tone.duration))
            }
        }
        // Аккорд из нескольких нот может сложиться выше единицы — это хрип.
        let peak = samples.map(abs).max() ?? 0
        if peak > 0.95 {
            let scale = 0.95 / peak
            samples = samples.map { $0 * scale }
        }
        return samples
    }

    /// Огибающая: короткая атака и экспоненциальное затухание к нулю в конце ноты.
    static func envelope(_ time: Double, _ duration: Double) -> Double {
        guard duration > 0, time >= 0, time <= duration else { return 0 }
        let rise = min(time / attack, 1)
        let fall = exp(-4 * time / duration) * (1 - time / duration)
        return rise * fall
    }
}
