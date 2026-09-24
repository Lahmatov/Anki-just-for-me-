import SwiftUI
import AJFMCore

/// Заставка при запуске: колода раскладывается и уходит, открывая приложение.
///
/// Устроена так, чтобы ничего не задерживать. Системный экран запуска статичен
/// и совпадает по цвету с первым кадром, поэтому стыка не видно; приложение
/// под заставкой уже загружено; нажатие пропускает её сразу. Правила показа —
/// полная раз в учебный день, дальше короткая, при «Уменьшении движения» —
/// никакой — живут в ядре, в `LaunchAnimationPolicy`, и покрыты тестами.
struct LaunchIntroView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.dayCutoffHour) private var cutoffHour = 4

    @State private var fanned = false
    @State private var pulse = false
    @State private var leaving = false
    @State private var glow = false
    @State private var finished = false

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            // Мягкое свечение цвета приложения за колодой.
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5, 0.5], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    .accentColor.opacity(0), .accentColor.opacity(0), .accentColor.opacity(0),
                    .accentColor.opacity(0), .accentColor.opacity(0.28), .accentColor.opacity(0),
                    .accentColor.opacity(0), .accentColor.opacity(0), .accentColor.opacity(0),
                ])
                .ignoresSafeArea()
                .opacity(glow ? 1 : 0)

            deck
                .scaleEffect(leaving ? 1.12 : (fanned ? 1 : 0.86))
        }
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityHidden(true)
        .task { await run() }
    }

    // MARK: - Колода

    private var deck: some View {
        ZStack {
            backCard(opacity: 0.35)
                .rotationEffect(.degrees(fanned ? -14 : -4))
                .offset(x: fanned ? -18 : 0, y: fanned ? -34 : 0)
            backCard(opacity: 0.6)
                .rotationEffect(.degrees(fanned ? -8 : -4))
                .offset(x: fanned ? -8 : 0, y: fanned ? -16 : 0)
            frontCard
                .rotationEffect(.degrees(-4))
        }
        .opacity(fanned ? 1 : 0)
    }

    private func backCard(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.accentColor.opacity(opacity))
            .frame(width: 180, height: 128)
    }

    private var frontCard: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .frame(width: 180, height: 128)
            .shadow(color: .accentColor.opacity(0.25), radius: 18, y: 10)
            .overlay {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Capsule().fill(Color.accentColor).frame(width: 74, height: 14)
                        Capsule().fill(Color.accentColor.opacity(0.4)).frame(width: 48, height: 9)
                    }
                    wave
                }
            }
    }

    /// Звуковая волна на карточке — голос и произношение, ради которых
    /// приложение и затевалось.
    private var wave: some View {
        HStack(spacing: 5) {
            ForEach(Array([0.35, 0.65, 1.0, 0.55].enumerated()), id: \.offset) { item in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 40 * item.element)
                    .scaleEffect(y: pulse ? 1 : 0.45, anchor: .center)
                    .animation(
                        .spring(duration: 0.35, bounce: 0.5)
                            .delay(Double(item.offset) * 0.05),
                        value: pulse)
            }
        }
    }

    // MARK: - Ход анимации

    private func run() async {
        let lastShown = UserDefaults.standard.object(
            forKey: SettingsKey.lastLaunchAnimation) as? Date
        let style = LaunchAnimationPolicy.style(
            reduceMotion: reduceMotion, lastFullShown: lastShown, cutoffHour: cutoffHour)

        switch style {
        case .none:
            finish()

        case .brief:
            // Колода уже разложена — просто уходит.
            fanned = true
            pulse = true
            glow = true
            try? await Task.sleep(for: .seconds(0.1))
            finish(duration: LaunchAnimationStyle.brief.duration)

        case .full:
            UserDefaults.standard.set(Date(), forKey: SettingsKey.lastLaunchAnimation)
            withAnimation(.easeOut(duration: 0.5)) { glow = true }
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) { fanned = true }
            try? await Task.sleep(for: .seconds(0.4))
            pulse = true
            try? await Task.sleep(for: .seconds(0.4))
            finish(duration: 0.4)
        }
    }

    private func finish(duration: TimeInterval = 0.25) {
        guard !finished else { return }
        finished = true
        withAnimation(.easeIn(duration: duration)) { leaving = true }
        Task {
            try? await Task.sleep(for: .seconds(duration))
            onFinish()
        }
    }
}
