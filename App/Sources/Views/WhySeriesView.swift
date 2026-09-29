import SwiftUI
import AJFMCore

/// «Почему это работает»: короткое объяснение и ссылки на статьи —
/// тем, кто сомневается, что сериал может быть учебником.
struct WhySeriesView: View {
    var body: some View {
        List {
            Section {
                MascotSays(mood: .cards,
                           text: tr("В сериале слова звучат в живой речи, с интонацией и в сюжете — "
                                        + "так они и запоминаются. Одни и те же герои и темы повторяют "
                                        + "слова из серии в серию, а это лучший тренажёр.",
                                    "Numa série as palavras aparecem em fala real, com entoação e dentro "
                                        + "da história — é assim que ficam. As mesmas personagens e temas "
                                        + "repetem as palavras de episódio para episódio: o melhor treino.",
                                    "In a series, words come in real speech, with intonation and inside a "
                                        + "story — that's how they stick. The same characters and topics "
                                        + "repeat words episode after episode: the best practice there is."),
                           size: 72)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section(tr("Почитать (на английском)", "Para ler (em inglês)", "Further reading")) {
                ForEach(LearningArticles.all) { article in
                    Link(destination: article.url) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(article.title)
                                .font(.app(.callout, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                            Text(article.summary)
                                .font(.app(.caption))
                                .foregroundStyle(Theme.muted)
                            Text(article.source)
                                .font(.app(.caption2, weight: .bold))
                                .foregroundStyle(Theme.primary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .themedScreen()
        .navigationTitle(tr("Почему сериалы", "Porquê séries", "Why TV shows"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
