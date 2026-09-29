import SwiftUI
import AJFMCore

/// Ссылка на источник данных о сериалах.
///
/// Данные TVmaze идут по лицензии CC BY-SA: пользоваться ими можно и в
/// платном приложении, но с указанием источника и ссылкой на него. Постеры
/// грузятся прямо с их адресов, а не копируются к нам — по их же совету:
/// если правообладатель попросит убрать картинку, это решится на их стороне.
struct TVMazeCredit: View {
    static let url = URL(string: "https://www.tvmaze.com")!

    var body: some View {
        Link(destination: Self.url) {
            Text(tr("Сериалы, серии и постеры — TVmaze (CC BY-SA)",
                    "Séries, episódios e cartazes — TVmaze (CC BY-SA)",
                    "Shows, episodes and posters — TVmaze (CC BY-SA)"))
                .font(.app(.caption2))
                .foregroundStyle(Theme.muted)
                .underline()
        }
        .frame(maxWidth: .infinity)
    }
}
