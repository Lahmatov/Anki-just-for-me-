import SwiftUI
import AJFMCore

// Анимации праздников и реакций. Физика и правила «когда» — в Core
// (Confetti, Shake, Celebration) и покрыты тестами; здесь только рисование.
//
// Всё уважает «Уменьшение движения» в настройках iOS: вместо полёта и
// тряски — ничего или спокойная смена состояния. Для кого-то движение на
// экране — не украшение, а головокружение.

extension Theme {
    /// Палитра северного сияния — того самого, что над Мончегорском.
    static let aurora: [Color] = [
        Color(red: 0.20, green: 0.90, blue: 0.62),
        Color(red: 0.16, green: 0.72, blue: 0.93),
        Color(red: 0.55, green: 0.40, blue: 0.95),
        Color(red: 0.98, green: 0.45, blue: 0.70),
        Color(red: 1.00, green: 0.78, blue: 0.20),
    ]
}

// MARK: - Конфетти

/// Одноразовый взрыв конфетти поверх экрана. Нажатия проходят насквозь,
/// через 2,6 секунды экран перестаёт перерисовываться.
struct ConfettiView: View {
    private let particles: [Confetti.Particle]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var finished = false

    init(seed: UInt64 = UInt64.random(in: 1 ... .max), count: Int = 90,
         origin: (x: Double, y: Double) = (0.5, 0.3)) {
        particles = Confetti.burst(count: count, seed: seed, origin: origin,
                                   colors: Theme.aurora.count)
    }

    var body: some View {
        // ZStack, а не Group: у пустой Group модификатор `.task` не на чем
        // запустить, а здесь контейнер есть всегда.
        ZStack {
            if !reduceMotion && !finished {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSince(start)
                    Canvas { canvas, size in
                        let opacity = Confetti.opacity(at: t)
                        guard opacity > 0 else { return }
                        for particle in particles {
                            draw(particle, at: t, opacity: opacity, in: &canvas, size: size)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            start = Date()
            try? await Task.sleep(for: .seconds(Confetti.lifetime))
            finished = true
        }
    }

    private func draw(_ particle: Confetti.Particle, at t: Double, opacity: Double,
                      in canvas: inout GraphicsContext, size: CGSize) {
        let position = Confetti.position(of: particle, at: t)
        var context = canvas
        context.opacity = opacity
        context.translateBy(x: position.x * size.width, y: position.y * size.height)
        context.rotate(by: .degrees(Confetti.rotation(of: particle, at: t) * 360))
        let side = particle.size
        let rect = CGRect(x: -side / 2, y: -side * 0.3, width: side,
                          height: particle.isRound ? side : side * 0.6)
        let shape = particle.isRound ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
        context.fill(shape, with: .color(Theme.aurora[particle.colorIndex % Theme.aurora.count]))
    }
}

// MARK: - Сияние

/// Медленно переливающееся северное сияние — фон для праздников.
/// Плывёт один узел сетки за другим; при «Уменьшении движения» — застывшее.
struct AuroraBackground: View {
    var intensity: Double = 0.55

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Через несколько секунд сияние застывает: переливаться, пока экран
    /// открыт, — это 30 кадров в секунду впустую и тёплый телефон.
    @State private var settled = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion || settled)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3, height: 3,
                points: points(at: t),
                colors: [
                    Theme.background, Theme.aurora[0].opacity(intensity), Theme.background,
                    Theme.aurora[1].opacity(intensity), Theme.aurora[2].opacity(intensity * 0.8),
                    Theme.aurora[0].opacity(intensity * 0.7),
                    Theme.background, Theme.aurora[3].opacity(intensity * 0.6), Theme.background,
                ])
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(8))
            settled = true
        }
    }

    /// Края сетки неподвижны, внутренние узлы плавают по синусам с разными
    /// периодами — поэтому рисунок не повторяется глазу заметно.
    private func points(at t: Double) -> [SIMD2<Float>] {
        func wave(_ period: Double, _ amplitude: Double, phase: Double = 0) -> Float {
            Float(sin(t * 2 * .pi / period + phase) * amplitude)
        }
        return [
            [0, 0], [0.5 + wave(11, 0.15), 0], [1, 0],
            [0, 0.5 + wave(13, 0.12, phase: 1)], [0.5 + wave(9, 0.18), 0.5 + wave(7, 0.14, phase: 2)],
            [1, 0.5 + wave(12, 0.12, phase: 3)],
            [0, 1], [0.5 + wave(10, 0.16, phase: 4), 1], [1, 1],
        ]
    }
}

// MARK: - Тряска

/// Покачивание «нет-нет» для неверного ответа. Каждое увеличение `trigger`
/// на единицу — одно покачивание (анимировать снаружи).
struct ShakeEffect: GeometryEffect {
    var trigger: CGFloat
    var amplitude: CGFloat = 9

    var animatableData: CGFloat {
        get { trigger }
        set { trigger = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        // Дробная часть — ход текущего покачивания: 0 → 1.
        let progress = Double(trigger - trigger.rounded(.down))
        let offset = Shake.offset(progress: progress, amplitude: Double(amplitude))
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

// MARK: - Мончик реагирует

/// Маленький Мончик рядом с карточкой: прыгает от радости на верный ответ,
/// мотает головой на неверный, задумывается на опечатку.
struct MascotReactionView: View {
    /// Вердикт последнего ответа; nil — ждёт ответа.
    let verdict: AnswerCheck.Verdict?
    /// Растёт с каждым ответом — чтобы реакция повторялась и на одинаковые вердикты.
    let trigger: Int
    var size: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Pose {
        var lift: CGFloat = 0
        var scale: CGFloat = 1
        var angle: Double = 0
    }

    var body: some View {
        Image(mood.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: Pose(), trigger: reduceMotion ? 0 : trigger) { content, pose in
                content
                    .scaleEffect(pose.scale, anchor: .bottom)
                    .rotationEffect(.degrees(pose.angle), anchor: .bottom)
                    .offset(y: pose.lift)
            } keyframes: { _ in
                KeyframeTrack(\.lift) {
                    if verdict == .correct {
                        SpringKeyframe(-18, duration: 0.18)
                        SpringKeyframe(0, duration: 0.35, spring: .bouncy)
                    } else {
                        LinearKeyframe(0, duration: 0.5)
                    }
                }
                KeyframeTrack(\.scale) {
                    if verdict == .correct {
                        CubicKeyframe(0.85, duration: 0.08)
                        CubicKeyframe(1.12, duration: 0.14)
                        SpringKeyframe(1, duration: 0.3)
                    } else {
                        LinearKeyframe(1, duration: 0.5)
                    }
                }
                KeyframeTrack(\.angle) {
                    switch verdict {
                    case .wrong:
                        CubicKeyframe(-10, duration: 0.08)
                        CubicKeyframe(10, duration: 0.12)
                        CubicKeyframe(-7, duration: 0.12)
                        CubicKeyframe(0, duration: 0.14)
                    case .typo:
                        SpringKeyframe(8, duration: 0.2)
                        SpringKeyframe(0, duration: 0.4)
                    default:
                        LinearKeyframe(0, duration: 0.5)
                    }
                }
            }
            .animation(.snappy, value: mood)
            .accessibilityHidden(true)
    }

    private var mood: MascotMood {
        switch verdict {
        case .correct: return .cheer
        case .typo: return .thinking
        case .wrong: return .oops
        case nil: return .cards
        }
    }
}

// MARK: - Счётчик

/// Число, которое набегает от старого значения к новому, а не прыгает:
/// «0% → 92%» читается как достижение, а просто «92%» — как справка.
struct CountingText: View, Animatable {
    var value: Double
    var suffix: String = ""

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))\(suffix)")
            .monospacedDigit()
    }
}

// MARK: - Баннер праздника

/// Праздник на весь экран: сияние, конфетти, прыгающий Мончик и фраза.
/// Закрывается касанием или сам через несколько секунд.
struct CelebrationOverlay: View {
    let title: String
    var subtitle: String?
    var onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            AuroraBackground(intensity: 0.7)
                .opacity(appeared ? 1 : 0)
            VStack(spacing: 14) {
                MascotView(mood: .cheer, size: 150)
                Text(title)
                    .font(.app(.title, weight: .black))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.app(.body))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(28)
            .glassEffect(.regular, in: .rect(cornerRadius: 32))
            .padding(24)
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
            ConfettiView()
        }
        .contentShape(Rectangle())
        .onTapGesture { close() }
        .onAppear {
            Haptics.success()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { appeared = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(3.5))
            close()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(tr("Коснись, чтобы закрыть", "Toca para fechar", "Tap to close"))
    }

    private func close() {
        guard appeared else { return }
        withAnimation(.easeOut(duration: 0.25)) { appeared = false }
        Task {
            try? await Task.sleep(for: .seconds(0.25))
            onDismiss()
        }
    }
}

// MARK: - Загрузка

/// Свой индикатор загрузки вместо системного колёсика: три «копытца»
/// разных цветов прыгают по очереди, с приплющиванием при приземлении.
/// Живёт, только пока виден, — загрузка короткая, телефон не греет.
struct MonchikLoader: View {
    var label: String?
    /// Крупный вариант — для экранов, где кроме загрузки ничего нет: с лосем.
    var large = false
    /// Один цвет для всех копытец — на цветной кнопке разноцветные теряются.
    var tint: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var colors: [Color] { [Theme.primary, Theme.orange, Theme.blue] }

    var body: some View {
        VStack(spacing: 12) {
            if large {
                MascotView(mood: .thinking, size: 84)
            }
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                HStack(spacing: large ? 10 : 7) {
                    ForEach(0..<3, id: \.self) { index in
                        hoof(index: index, time: t)
                    }
                }
                .frame(height: dot * 2.4, alignment: .bottom)
            }
            if let label {
                Text(label)
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? tr("Загрузка", "A carregar", "Loading"))
    }

    private var dot: CGFloat { large ? 14 : 9 }

    private func hoof(index: Int, time: Double) -> some View {
        // Прыжок — полусинус с периодом 0.9 с, копытца сдвинуты по фазе.
        let phase = (time / 0.9 + Double(index) * 0.18).truncatingRemainder(dividingBy: 1)
        let lift = max(0, sin(phase * 2 * .pi))
        // У земли копытце приплющено, в воздухе вытянуто.
        let squash = 1 - 0.25 * (1 - lift)
        return Capsule()
            .fill((tint ?? colors[index]).gradient)
            .frame(width: dot, height: dot * (0.8 + 0.4 * lift))
            .scaleEffect(x: 1 / squash, y: squash, anchor: .bottom)
            .offset(y: -CGFloat(lift) * dot * 1.2)
    }
}
