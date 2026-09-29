import SwiftUI
import SwiftData
import AJFMCore

/// «Recap после серии»: досмотрел — одна кнопка, три коротких шага.
/// Пять слов из серии, три вопроса Мончика, пересказ.
///
/// Всё это было и раньше, но на трёх разных экранах, и после серии до них
/// никто не доходил. Здесь шаги собраны в один путь с отметками: видно,
/// что сделано и что следующее, и можно прерваться и вернуться.
struct EpisodeRecapView: View {
    let show: TrackedShow
    let episode: EpisodeContext

    @Environment(\.modelContext) private var context
    @State private var progress = RecapProgress()
    @State private var deck: Deck?
    @State private var hasCatalogWords = false
    @State private var showDeckRequest = false
    @State private var installError: String?
    @State private var celebrate = false

    private var service: RecapService { RecapService(context: context) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.stackSpacing) {
                header
                wordsStep
                questionsStep
                retellStep
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Recap")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .sheet(isPresented: $showDeckRequest, onDismiss: refresh) {
            DeckRequestView(initialTopic: "\(episode.showName) \(episode.episode.code)", episode: episode)
        }
        .overlay {
            if celebrate {
                CelebrationOverlay(
                    title: tr("Серия разобрана!", "Episódio arrumado!", "Episode wrapped up!"),
                    subtitle: tr("Слова, вопросы и пересказ — всё. Теперь эта серия и правда твоя.",
                                 "Palavras, perguntas e reconto — feito. Agora este episódio é mesmo teu.",
                                 "Words, questions and a retelling — done. This episode is really yours now.")
                ) { celebrate = false }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.app, value: celebrate)
        .animation(.app, value: progress)
        .alert(CommonText.failedTitle,
               isPresented: Binding(get: { installError != nil }, set: { if !$0 { installError = nil } }),
               presenting: installError) { _ in
            Button(CommonText.gotIt) {}
        } message: { Text($0) }
    }

    // MARK: - Заголовок

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            MascotSays(
                mood: progress.isComplete ? .cheer : .hello,
                text: progress.isComplete
                    ? tr("Всё пройдено! Можно смотреть следующую.", "Tudo feito! Podes ver o próximo.",
                         "All done! On to the next one.")
                    : tr("Три шага минут на десять — и серия останется в голове, а не только в истории просмотров.",
                         "Três passos, uns dez minutos — e o episódio fica na cabeça, não só no histórico.",
                         "Three steps, about ten minutes — and the episode stays in your head, not just your history."),
                size: 64)
            Text(episode.title)
                .font(.app(.subheadline, weight: .bold))
                .foregroundStyle(Theme.muted)
            ChunkyProgressBar(value: progress.fraction, tint: Theme.green)
                .accessibilityIdentifier("recap.progress")
        }
        .cardSurface()
    }

    // MARK: - Шаги

    @ViewBuilder
    private var wordsStep: some View {
        let title = tr("\(RecapPlan.words) слов из серии", "\(RecapPlan.words) palavras do episódio",
                       "\(RecapPlan.words) words from the episode")
        if let deck {
            NavigationLink {
                ReviewSessionView(deck: deck, limit: RecapPlan.words) { finish(.words) }
            } label: {
                stepCard(.words, number: 1, title: title,
                         subtitle: tr("Быстро повторить слова этой серии", "Rever depressa as palavras deste episódio",
                                      "A quick review of this episode's words"),
                         symbol: "rectangle.stack.fill", color: Theme.blue)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recap.words")
        } else {
            Button {
                getWords()
            } label: {
                stepCard(.words, number: 1, title: title,
                         subtitle: hasCatalogWords
                            ? tr("Готовые слова есть — добавлю одним касанием",
                                 "Há palavras prontas — junto com um toque",
                                 "Ready words exist — one tap to add them")
                            : tr("Сначала подберу слова к серии", "Primeiro escolho palavras para o episódio",
                                 "First I'll pick words for the episode"),
                         symbol: hasCatalogWords ? "books.vertical.fill" : "sparkles", color: Theme.blue)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recap.words")
        }
    }

    private var questionsStep: some View {
        NavigationLink {
            EpisodeDiscussionView(episode: episode, questions: EpisodeDiscussion.recapQuestions) {
                finish(.questions)
            }
        } label: {
            stepCard(.questions, number: 2,
                     title: tr("3 вопроса Мончика", "3 perguntas do Monchik", "3 questions from Monchik"),
                     subtitle: tr("Ответь голосом или текстом — поправлю по ходу",
                                  "Responde por voz ou texto — corrijo pelo caminho",
                                  "Answer by voice or text — I'll correct as we go"),
                     symbol: "bubble.left.and.bubble.right.fill", color: Theme.green)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recap.questions")
    }

    private var retellStep: some View {
        NavigationLink {
            RetellView(episode: episode) { finish(.retell) }
        } label: {
            stepCard(.retell, number: 3,
                     title: tr("Пересказ", "Reconto", "Retelling"),
                     subtitle: tr("Расскажи серию своими словами — проверю понимание",
                                  "Conta o episódio por palavras tuas — verifico a compreensão",
                                  "Tell the episode in your own words — I'll check understanding"),
                     symbol: "text.bubble.fill", color: Theme.purple)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recap.retell")
    }

    private func stepCard(_ step: RecapStep, number: Int, title: String, subtitle: String,
                          symbol: String, color: Color) -> some View {
        let done = progress.isDone(step)
        let isNext = progress.next == step
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(done ? Theme.green : (isNext ? color : Theme.border))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy))
                } else {
                    Text("\(number)").font(.app(.headline, weight: .heavy))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(.body, weight: .bold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.app(.caption)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(done ? Theme.muted : color)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Следующий шаг обведён своим цветом: глаз сразу находит, куда нажать.
        .panel(border: isNext ? color : Theme.border)
        .opacity(done ? 0.75 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? tr("сделано", "feito", "done") : "")
    }

    // MARK: - Действия

    private func refresh() {
        progress = service.progress(for: episode)
        deck = service.deck(for: episode)
        hasCatalogWords = deck == nil && service.catalogEpisode(for: episode) != nil
    }

    private func getWords() {
        guard hasCatalogWords else {
            showDeckRequest = true
            return
        }
        do {
            deck = try service.installFromCatalog(for: episode)
            hasCatalogWords = false
            Haptics.success()
        } catch {
            Log.failure(.importing, "Слова серии из каталога не добавились", error)
            installError = error.localizedDescription
        }
    }

    private func finish(_ step: RecapStep) {
        let wasComplete = progress.isComplete
        progress = service.complete(step, for: episode)
        if progress.isComplete, !wasComplete {
            Haptics.success()
            // Праздник (и его фанфары) — когда человек вернётся на этот экран, а не поверх шага.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { celebrate = true }
        }
    }
}
