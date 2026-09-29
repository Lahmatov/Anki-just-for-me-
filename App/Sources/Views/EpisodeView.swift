import SwiftUI
import SwiftData
import AJFMCore

/// Серия: отметка «посмотрел», слова, пересказ и разговор с Мончиком.
///
/// Описание скрыто, пока серия не отмечена: это спойлер, а смотрят сюда
/// чаще всего перед просмотром — за словами.
struct EpisodeView: View {
    let show: TrackedShow
    let episode: EpisodeContext

    @Environment(\.modelContext) private var context
    @State private var revealSummary = false
    @State private var showDeckRequest = false
    @State private var recap = RecapProgress()

    private var info: EpisodeInfo { episode.episode }
    private var watched: Bool { show.watched.contains(info.key) }
    private var aired: Bool { info.isAired(today: ShowProgress.today()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.stackSpacing) {
                header
                watchButton
                summaryCard
                actions
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(info.code)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { recap = RecapService(context: context).progress(for: episode) }
        .sheet(isPresented: $showDeckRequest) {
            DeckRequestView(initialTopic: "\(episode.showName) \(info.code)", episode: episode)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            if let url = show.posterURL.flatMap({ URL(string: $0) }) {
                CoverImage(url: url, width: 64)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.showName)
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.muted)
                Text(info.name.isEmpty ? info.code : info.name)
                    .font(.app(.title2))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 10) {
                    if let date = info.airdate { Label(date, systemImage: "calendar") }
                    if let runtime = info.runtime { Label(Counted.minutes(runtime), systemImage: "clock") }
                }
                .font(.app(.caption))
                .foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder
    private var watchButton: some View {
        if aired {
            Button {
                Haptics.tap()
                ShowService(context: context).setWatched(info.key, !watched, in: show)
                if !watched { Haptics.success() }
            } label: {
                Label(watched ? tr("Просмотрена", "Visto", "Watched")
                              : tr("Отметить просмотренной", "Marcar como visto", "Mark as watched"),
                      systemImage: watched ? "checkmark.circle.fill" : "circle")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChunkyButtonStyle(kind: watched ? .secondary : .primary))
        } else {
            MascotSays(mood: .sleepy,
                       text: tr("Серия ещё не вышла.", "O episódio ainda não saiu.",
                                "This episode hasn't aired yet."),
                       size: 64)
        }
    }

    @ViewBuilder
    private var summaryCard: some View {
        if !info.summary.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("О чём серия", "Sobre o episódio", "What it's about"))
                    .font(.app(.headline))
                    .foregroundStyle(Theme.ink)
                if watched || revealSummary {
                    Text(info.summary)
                        .font(.app(.body))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                } else {
                    Text(info.summary)
                        .font(.app(.body))
                        .blur(radius: 7)
                        .accessibilityHidden(true)
                        .overlay {
                            Button(tr("Показать — это спойлер", "Mostrar — é spoiler",
                                      "Show — it's a spoiler")) {
                                withAnimation { revealSummary = true }
                            }
                            .buttonStyle(.chunkySecondary)
                        }
                }
            }
            .cardSurface()
        }
    }

    /// Главная кнопка после просмотра: весь разбор серии в одном месте.
    private var recapButton: some View {
        NavigationLink {
            EpisodeRecapView(show: show, episode: episode)
        } label: {
            HStack(spacing: 14) {
                MascotView(mood: recap.isComplete ? .cheer : .hello, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recap")
                        .font(.app(.title3, weight: .heavy))
                        .foregroundStyle(Theme.onPrimary)
                    Text(recap.isComplete
                         ? tr("Серия разобрана", "Episódio arrumado", "Episode wrapped up")
                         : tr("5 слов · 3 вопроса · пересказ", "5 palavras · 3 perguntas · reconto",
                              "5 words · 3 questions · retelling"))
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.onPrimary.opacity(0.9))
                    if recap.fraction > 0, !recap.isComplete {
                        ChunkyProgressBar(value: recap.fraction, tint: Theme.gold, height: 8)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(fill: Theme.primary, border: Theme.primaryLip)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("episode.recap")
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if watched { recapButton }
            CardSectionHeader(title: tr("С этой серией", "Com este episódio", "With this episode"))
            Button {
                showDeckRequest = true
            } label: {
                actionLabel(tr("Слова к серии", "Palavras do episódio", "Words for the episode"),
                            subtitle: tr("Выучи до просмотра — смотреть будет легче",
                                         "Aprende antes de ver — vai ser mais fácil",
                                         "Learn them before watching — it'll be easier"),
                            symbol: "sparkles", color: Theme.blue)
            }
            .buttonStyle(.plain)

            if watched {
                NavigationLink {
                    RetellView(episode: episode)
                } label: {
                    actionLabel(tr("Пересказать", "Recontar", "Retell it"),
                                subtitle: tr("Расскажи, о чём была серия, — проверю понимание",
                                             "Conta de que tratou — verifico a compreensão",
                                             "Say what it was about — I'll check understanding"),
                                symbol: "text.bubble.fill", color: Theme.purple)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    EpisodeDiscussionView(episode: episode)
                } label: {
                    actionLabel(tr("Поговорить с Мончиком", "Conversar com o Monchik",
                                   "Chat with Monchik"),
                                subtitle: tr("Шесть вопросов о серии, поправки по ходу",
                                             "Seis perguntas sobre o episódio, com correções",
                                             "Six questions about the episode, with tips"),
                                symbol: "bubble.left.and.bubble.right.fill", color: Theme.green)
                }
                .buttonStyle(.plain)
            } else {
                Text(tr("Отметь серию просмотренной — откроются пересказ и разговор о ней.",
                        "Marca o episódio como visto — abrem-se o reconto e a conversa.",
                        "Mark the episode as watched to unlock retelling and chat."))
                    .font(.app(.footnote))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func actionLabel(_ title: String, subtitle: String, symbol: String, color: Color)
        -> some View {
        HStack(spacing: 14) {
            IconBadge(systemName: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(.body, weight: .bold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.app(.caption)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .contentShape(Rectangle())
    }
}
