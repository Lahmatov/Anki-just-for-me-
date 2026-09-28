import SwiftUI
import AJFMCore

/// Заставка при запуске: лось Мончик выпрыгивает, машет и уходит, открывая приложение.
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

    // MARK: - Лось

    private var deck: some View {
        VStack(spacing: 18) {
            ZStack {
                // Сияние за лосем — зелёное, как над Мончетундрой.
                Circle()
                    .fill(Theme.primary.opacity(0.14))
                    .frame(width: 230, height: 230)
                    .scaleEffect(pulse ? 1 : 0.7)
                    .animation(.spring(duration: 0.5, bounce: 0.4), value: pulse)
                Image(MascotMood.hello.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .offset(y: fanned ? 0 : 60)
            }
            // Название одно на всех языках: recap — краткий пересказ серии,
            // ровно то, вокруг чего построено приложение.
            Text("Recap")
                .font(.display(.largeTitle))
                .foregroundStyle(Theme.ink)
                .opacity(glow ? 1 : 0)
        }
        .opacity(fanned ? 1 : 0)
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
