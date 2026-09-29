import Foundation

/// Небольшой генератор с зерном (SplitMix64, Vigna). Системный генератор
/// зерна не принимает, а порядок теста уровня и взрыв конфетти должны
/// воспроизводиться — в тестах и на экране.
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

    /// Число в [0, 1): старшие 53 бита — ровно столько вмещает Double.
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }
}
