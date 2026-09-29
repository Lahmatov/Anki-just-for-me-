import Foundation

/// Физика конфетти — без SwiftUI, чтобы её можно было проверить тестами.
///
/// Экран только рисует: где каждая бумажка через `t` секунд и насколько
/// она прозрачна, решается здесь. Разброс — от собственного генератора с
/// зерном: один и тот же взрыв при одном зерне выглядит одинаково, а
/// значит, его можно проверить и воспроизвести.
public enum Confetti {

    public struct Particle: Equatable, Sendable {
        /// Старт в долях экрана: 0…1 по ширине и высоте.
        public var x: Double
        public var y: Double
        /// Скорость в долях экрана в секунду; y растёт вниз, как на экране.
        public var vx: Double
        public var vy: Double
        /// Вращение, оборотов в секунду (знак — направление).
        public var spin: Double
        /// Номер цвета в палитре экрана.
        public var colorIndex: Int
        /// Сторона бумажки в точках.
        public var size: Double
        /// Прямоугольник или кружок — чтобы взрыв не выглядел штампованным.
        public var isRound: Bool

        public init(x: Double, y: Double, vx: Double, vy: Double, spin: Double,
                    colorIndex: Int, size: Double, isRound: Bool) {
            self.x = x
            self.y = y
            self.vx = vx
            self.vy = vy
            self.spin = spin
            self.colorIndex = colorIndex
            self.size = size
            self.isRound = isRound
        }
    }

    /// Сколько живёт взрыв. Дольше — конфетти мешает нажать «Готово».
    public static let lifetime = 2.6
    /// Ускорение вниз в долях экрана за секунду².
    public static let gravity = 1.4
    /// Сопротивление воздуха: бумажки не летят как пули.
    public static let drag = 0.9

    /// Взрыв из точки `origin` (в долях экрана) вверх веером.
    public static func burst(count: Int, seed: UInt64, origin: (x: Double, y: Double) = (0.5, 0.35),
                             colors: Int = 5) -> [Particle] {
        guard count > 0 else { return [] }
        var random = SplitMix64(seed: seed)
        return (0..<count).map { _ in
            // Веер от −150° до −30°: вверх и в стороны, почти никогда прямо вниз.
            let angle = (-150.0 + 120.0 * random.nextUnit()) * .pi / 180
            let speed = 0.55 + 0.75 * random.nextUnit()
            return Particle(
                x: origin.x, y: origin.y,
                vx: cos(angle) * speed, vy: sin(angle) * speed,
                spin: (random.nextUnit() * 2 - 1) * 2.5,
                colorIndex: Int(random.next() % UInt64(max(colors, 1))),
                size: 6 + 6 * random.nextUnit(),
                isRound: random.next() % 4 == 0)
        }
    }

    /// Где бумажка через `t` секунд. Скорость гаснет от сопротивления,
    /// тяжесть тянет вниз: сначала вверх, потом плавно падает.
    public static func position(of particle: Particle, at t: Double) -> (x: Double, y: Double) {
        let time = max(0, t)
        // ∫ e^(−k t) dt = (1 − e^(−k t)) / k — путь при затухающей скорости.
        let travelled = (1 - exp(-drag * time)) / drag
        return (particle.x + particle.vx * travelled,
                particle.y + particle.vy * travelled + 0.5 * gravity * time * time)
    }

    /// Угол поворота в оборотах.
    public static func rotation(of particle: Particle, at t: Double) -> Double {
        particle.spin * max(0, t)
    }

    /// Непрозрачность: полная, а последнюю треть жизни — плавно в ноль.
    public static func opacity(at t: Double) -> Double {
        let fadeStart = lifetime * 2 / 3
        if t <= fadeStart { return t < 0 ? 0 : 1 }
        return max(0, 1 - (t - fadeStart) / (lifetime - fadeStart))
    }

    public static func isFinished(at t: Double) -> Bool { t >= lifetime }
}

/// Небольшой генератор с зерном (SplitMix64): системный `random` не
/// повторяется между запусками, а взрыв должен.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Число в [0, 1).
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

/// Покачивание «нет-нет» — для неверного ответа и лося, который не согласен.
public enum Shake {
    /// Сдвиг по горизонтали на доле анимации `progress` (0…1): `shakes`
    /// полных качаний с затуханием, в начале и в конце — ровно ноль.
    public static func offset(progress: Double, amplitude: Double = 10, shakes: Double = 3) -> Double {
        let p = min(max(progress, 0), 1)
        return amplitude * sin(p * .pi * 2 * shakes) * (1 - p)
    }
}
