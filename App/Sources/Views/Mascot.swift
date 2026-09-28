import SwiftUI
import AJFMCore

/// Лось Мончик из Мончегорска — маскот приложения.
///
/// Персонаж нужен не для украшения: пустой экран с лосем, который спит,
/// читается как «всё сделано», а не как «сломалось», а радующийся лось
/// после сессии — награда, которую видно раньше цифр. Рисунки —
/// векторные, собираются tools/make_mascot.py.
enum Mascot {
    static var name: String { tr("Мончик", "Monchik", "Monchik") }
}

enum MascotMood: String, CaseIterable {
    case hello, thinking, cheer, sleepy, oops, cards

    var assetName: String { "Mascot" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

struct MascotView: View {
    var mood: MascotMood = .hello
    var size: CGFloat = 120

    @State private var appeared = false

    var body: some View {
        Image(mood.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            // Один прыжок при появлении, без вечной анимации: постоянно
            // шевелящийся лось грел бы телефон и отвлекал от карточек.
            .scaleEffect(appeared ? 1 : 0.8, anchor: .bottom)
            .animation(.spring(response: 0.45, dampingFraction: 0.55), value: appeared)
            .onAppear { appeared = true }
            .accessibilityLabel(Mascot.name)
    }
}

/// Лось с репликой в облачке — для пустых экранов, подсказок и итогов.
struct MascotSays: View {
    var mood: MascotMood = .hello
    let text: String
    var size: CGFloat = 92

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            MascotView(mood: mood, size: size)
            Text(text)
                .font(.app(.callout, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .panel(radius: 16)
                .overlay(alignment: .leading) {
                    // Хвостик облачка — к лосю.
                    BubbleTail()
                        .fill(Theme.surface)
                        .overlay(BubbleTail().stroke(Theme.border, lineWidth: Theme.stroke))
                        .frame(width: 10, height: 16)
                        .offset(x: -8, y: -2)
                }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// Пустой экран с лосем: картинка, заголовок, пояснение и действие.
struct MascotEmptyState<Actions: View>: View {
    var mood: MascotMood
    let title: String
    var message: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 14) {
            MascotView(mood: mood, size: 150)
            Text(title)
                .font(.app(.title2))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.app(.callout))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            actions()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

extension MascotEmptyState where Actions == EmptyView {
    init(mood: MascotMood, title: String, message: String? = nil) {
        self.init(mood: mood, title: title, message: message) { EmptyView() }
    }
}
