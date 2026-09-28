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

    /// Пиксельная колода: карточки не поворачиваются, а раскладываются
    /// ступеньками — поворот размывал бы пиксельные рамки.
    private var deck: some View {
        VStack(spacing: 28) {
            ZStack {
                backCard(Retro.secondary)
                    .offset(x: fanned ? -24 : 0, y: fanned ? -24 : 0)
                backCard(Retro.primary.opacity(0.55))
                    .offset(x: fanned ? -12 : 0, y: fanned ? -12 : 0)
                frontCard
            }
            Text(tr("Карточки", "Cartões", "Flashcards"))
                .font(.display(.title2))
                .foregroundStyle(Retro.ink)
                .opacity(glow ? 1 : 0)
        }
        .opacity(fanned ? 1 : 0)
    }

    private func backCard(_ color: Color) -> some View {
        Color.clear
            .frame(width: 180, height: 124)
            .pixelFrame(fill: color, shadow: nil)
    }

    private var frontCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(Retro.ink).frame(width: 72, height: 12)
                Rectangle().fill(Retro.primary).frame(width: 48, height: 9)
            }
            wave
        }
        .frame(width: 180, height: 124)
        .pixelFrame(fill: Retro.surface, shadow: Retro.shadow)
    }

    /// Звуковая волна на карточке — голос и произношение, ради которых
    /// приложение и затевалось.
    private var wave: some View {
        HStack(spacing: 4) {
            ForEach(Array([0.35, 0.65, 1.0, 0.55].enumerated()), id: \.offset) { item in
                Rectangle()
                    .fill(Retro.primary)
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
            finish(duration: style.duration)

        case .full:
            UserDefaults.standard.set(Date(), forKey: SettingsKey.lastLaunchAnimation)
            // Фазы — доли общей длительности из политики: так обещанный
            // в тестах предел и реальная анимация не разъедутся.
            let phase = style.duration / 3
            withAnimation(.easeOut(duration: phase)) { glow = true }
            withAnimation(.spring(duration: phase, bounce: 0.3)) { fanned = true }
            try? await Task.sleep(for: .seconds(phase))
            pulse = true
            try? await Task.sleep(for: .seconds(phase))
            finish(duration: phase)
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
