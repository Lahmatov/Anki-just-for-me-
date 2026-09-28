import SwiftUI
import AJFMCore

/// Тест уровня: карточки словаря с переворотом, затем грамматика.
///
/// Карточка: слово — «знаю» или «не знаю». На «знаю» она переворачивается
/// и показывает значение, и человек сам отмечает, угадал ли. Среди слов
/// есть выдуманные, и об этом говорится заранее — честность ответов важнее
/// скорости. Вся логика хода — в `PlacementSession` (ядро, с тестами),
/// экран только рисует.
struct PlacementTestView: View {
    var onFinish: (CEFRLevel) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var session = PlacementSession(seed: UInt64.random(in: 1...UInt64.max))
    @State private var started = false
    /// Выбранный вариант грамматики — пока подсвечен ответ, нажатия гасятся.
    @State private var picked: String?

    var body: some View {
        NavigationStack {
            Group {
                if !started {
                    introView
                } else {
                    switch session.stage {
                    case .card(let index, let revealed):
                        cardView(session.items[index], revealed: revealed)
                    case .grammar:
                        grammarView
                    case .finished:
                        resultView(session.outcome)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(tr("Тест уровня", "Teste de nível", "Level test"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if started, session.stage != .finished {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Haptics.tap()
                            goBack()
                        } label: {
                            Label(CommonText.back, systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                        }
                        .disabled(picked != nil)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(CommonText.close) { dismiss() }
                }
            }
        }
    }

    private func goBack() {
        withAnimation(.snappy) {
            if session.canGoBack {
                session.goBack()
            } else {
                // С первой карточки — к объяснению правил.
                started = false
            }
        }
    }

    // MARK: - Вступление

    private var introView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 0)
            MascotSays(mood: .thinking,
                       text: tr("Давай узнаем твой уровень!", "Vamos descobrir o teu nível!",
                                "Let's find out your level!"))
            VStack(alignment: .leading, spacing: 14) {
                let count = Counted.words(session.items.count)
                point("rectangle.on.rectangle.angled",
                      tr("Часть 1 — \(count) на карточках. Знаешь слово — переверни "
                            + "и проверь себя. Не знаешь — дальше.",
                         "Parte 1 — \(count) em cartões. Se conheces a palavra, vira o "
                            + "cartão e confirma. Se não, segue.",
                         "Part 1 — \(count) on cards. Know the word? Flip it and check "
                            + "yourself. Don't? Move on."))
                point("questionmark.diamond",
                      tr("Часть слов выдумана. «Знаю» на выдумку снижает результат — "
                            + "так тест остаётся честным.",
                         "Algumas palavras são inventadas. Dizer «sei» a uma delas baixa o "
                            + "resultado — é assim que o teste se mantém honesto.",
                         "Some words are made up. Saying “I know” to one lowers the "
                            + "result — that's how the test stays honest."))
                point("text.book.closed",
                      tr("Часть 2 — \(GrammarTest.questions.count) вопросов на грамматику: "
                            + "выбери, как правильно.",
                         "Parte 2 — \(GrammarTest.questions.count) perguntas de gramática: "
                            + "escolhe a forma certa.",
                         "Part 2 — \(GrammarTest.questions.count) grammar questions: "
                            + "pick the right form."))
                point("clock", tr("Минут пять. Уровень потом можно поменять руками.",
                                  "Uns cinco minutos. Depois podes mudar o nível à mão.",
                                  "About five minutes. You can change the level by hand later."))
            }
            .cardSurface()
            Spacer(minLength: 0)
            primaryButton(tr("Начать", "Começar", "Start")) {
                withAnimation(.snappy) { started = true }
            }
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 24)
            Text(text)
                .font(.app(.callout))
                .foregroundStyle(Theme.ink)
        }
    }

    // MARK: - Карточка словаря

    private func cardView(_ item: PlacementTest.Item, revealed: Bool) -> some View {
        VStack(spacing: 20) {
            progress

            Spacer(minLength: 0)

            FlipCard(flipped: revealed) {
                VStack(spacing: 12) {
                    Text(tr("Знаешь это слово?", "Conheces esta palavra?",
                            "Do you know this word?"))
                        .font(.app(.callout, weight: .bold))
                        .foregroundStyle(Theme.muted)
                    Text(item.word)
                        .font(.app(.largeTitle))
                        .foregroundStyle(Theme.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            } back: {
                back(of: item)
            }
            // Новая карточка — новое представление: переворот не должен
            // «доигрывать» на следующем слове.
            .id(item.word)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)))

            Spacer(minLength: 0)

            cardButtons(item, revealed: revealed)
        }
    }

    @ViewBuilder
    private func back(of item: PlacementTest.Item) -> some View {
        if let gloss = PlacementTest.gloss(for: item.word, language: Loc.language) {
            VStack(spacing: 10) {
                Text(item.word)
                    .font(.app(.title3))
                    .foregroundStyle(Theme.muted)
                Text(gloss)
                    .font(.app(.title2))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text(tr("Ты так и понял?", "Era isto que pensavas?", "Is that what you thought?"))
                    .font(.app(.callout, weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .padding(.top, 6)
            }
        } else {
            VStack(spacing: 8) {
                MascotView(mood: .oops, size: 84)
                Text(tr("Такого слова нет!", "Esta palavra não existe!", "That's not a word!"))
                    .font(.app(.title2))
                    .foregroundStyle(Theme.ink)
                Text(tr("«\(item.word)» — выдумка. Они подмешаны, чтобы тест был честным.",
                        "«\(item.word)» é inventada. Estão misturadas para o teste ser honesto.",
                        "“\(item.word)” is made up. They're mixed in to keep the test honest."))
                    .font(.app(.callout))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func cardButtons(_ item: PlacementTest.Item, revealed: Bool) -> some View {
        HStack(spacing: 12) {
            if !revealed {
                answerButton(tr("Не знаю", "Não sei", "Don't know"), kind: .secondary) {
                    session.claim(known: false)
                }
                answerButton(tr("Знаю", "Sei", "I know"), kind: .primary) {
                    session.claim(known: true)
                }
            } else if item.isReal {
                answerButton(tr("Нет", "Não", "No"), kind: .secondary) {
                    session.confirm(understood: false)
                }
                answerButton(tr("Да, угадал", "Sim, acertei", "Yes, got it"), kind: .primary) {
                    session.confirm(understood: true)
                }
            } else {
                answerButton(CommonText.next, kind: .primary) { session.next() }
            }
        }
        .controlSize(.large)
    }

    private func answerButton(
        _ title: String, kind: ChunkyButtonStyle.Kind, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy) { action() }
        } label: {
            Text(title)
                .font(.app(.headline))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(ChunkyButtonStyle(kind: kind))
    }

    private var progress: some View {
        HStack(spacing: 12) {
            ChunkyProgressBar(value: Double(session.completedSteps),
                              total: Double(max(session.totalSteps, 1)))
            Text("\(session.completedSteps + 1)/\(session.totalSteps)")
                .font(.app(.caption, weight: .bold))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
        }
    }

    // MARK: - Грамматика

    @ViewBuilder
    private var grammarView: some View {
        if let question = session.currentQuestion {
            VStack(alignment: .leading, spacing: 18) {
                progress

                if case .grammar(0) = session.stage {
                    MascotSays(mood: .thinking,
                               text: tr("Теперь грамматика. Выбери, как правильно.",
                                        "Agora gramática. Escolhe a forma certa.",
                                        "Now grammar. Pick the right option."),
                               size: 72)
                }

                Text(question.prompt)
                    .font(.app(.title2))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
                    .id(question.id)
                    .transition(.move(edge: .trailing).combined(with: .opacity))

                VStack(spacing: 10) {
                    ForEach(session.currentOptions, id: \.self) { option in
                        optionButton(option, question: question)
                    }
                }

                Spacer(minLength: 0)

                Button(tr("Пропустить грамматику", "Saltar a gramática", "Skip grammar")) {
                    withAnimation(.snappy) { session.skipGrammar() }
                }
                .font(.app(.callout, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .disabled(picked != nil)
            }
        }
    }

    private func optionButton(_ option: String, question: GrammarTest.Question) -> some View {
        let isAnswer = option == question.answer
        let showing = picked != nil
        let color: Color? = !showing ? nil
            : isAnswer ? Theme.green
            : option == picked ? Theme.red : nil
        return Button {
            guard picked == nil else { return }
            picked = option
            if isAnswer { Haptics.success() } else { Haptics.failure() }
            // Короткая подсветка — видно, где ошибся, — и дальше.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(.snappy) {
                    session.answer(option)
                    picked = nil
                }
            }
        } label: {
            HStack {
                Text(option)
                    .font(.app(.body, weight: .bold))
                Spacer()
                if let color {
                    Image(systemName: isAnswer ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(color)
                }
            }
            .foregroundStyle(color ?? Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.chunkySecondary)
        .overlay {
            if let color {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(color, lineWidth: Theme.stroke + 1)
                    .padding(.bottom, Theme.lip)
            }
        }
        .allowsHitTesting(picked == nil)
    }

    // MARK: - Итог

    private func resultView(_ outcome: PlacementSession.Outcome) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                MascotView(mood: .cheer, size: 150)
                Text(outcome.level.rawValue)
                    .font(.display(.largeTitle))
                    .scaleEffect(1.6)
                    .foregroundStyle(Theme.primary)
                    .padding(.vertical, 10)

                VStack(spacing: 12) {
                    resultRow(
                        tr("Словарь", "Vocabulário", "Vocabulary"),
                        value: outcome.vocabulary.level.rawValue,
                        detail: "≈ \(outcome.vocabulary.estimatedWords) "
                            + tr("частых слов из сериалов", "palavras frequentes das séries",
                                 "common words from TV shows"))
                    Divider()
                    resultRow(
                        tr("Грамматика", "Gramática", "Grammar"),
                        value: outcome.grammar?.rawValue ?? "—",
                        detail: outcome.grammar == nil
                            ? tr("пропущена", "saltada", "skipped") : nil)
                }
                .cardSurface()

                Text(tr("Итог — среднее, с округлением вниз. Наборы будут подбираться "
                            + "на ступень выше — уже не очевидные, но ещё частые слова.",
                        "O resultado é a média, arredondada para baixo. Os baralhos ficam um "
                            + "degrau acima — palavras já não óbvias, mas ainda frequentes.",
                        "The result is the average, rounded down. Decks will be one step "
                            + "above — words no longer obvious but still common."))
                    .font(.app(.subheadline))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)

                if !outcome.vocabulary.isReliable {
                    Label(
                        tr("На выдуманные слова часто отвечалось «знаю» — оценка может "
                                + "быть неточной. Можно пройти ещё раз.",
                           "Muitas palavras inventadas tiveram «sei» — a estimativa pode "
                                + "não ser exata. Podes repetir o teste.",
                           "Many made-up words got “I know” — the estimate may be off. "
                                + "You can take the test again."),
                        systemImage: "exclamationmark.triangle")
                        .font(.app(.footnote))
                        .foregroundStyle(Theme.ink)
                        .padding()
                        .panel(fill: Theme.orange.opacity(0.15), border: Theme.orange, lip: false)
                }

                primaryButton(tr("Сохранить уровень", "Guardar o nível", "Save the level")) {
                    Log.info(
                        .app, "Тест уровня пройден",
                        detail: "итог: \(outcome.level.rawValue), словарь: "
                            + "\(outcome.vocabulary.level.rawValue) "
                            + "(\(outcome.vocabulary.estimatedWords)), грамматика: "
                            + (outcome.grammar?.rawValue ?? "пропущена"))
                    onFinish(outcome.level)
                    dismiss()
                }
                Button(tr("Пройти ещё раз", "Repetir o teste", "Take it again")) { restart() }
                    .font(.app(.callout, weight: .bold))
            }
        }
        .onAppear { Haptics.success() }
    }

    private func resultRow(_ title: String, value: String, detail: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(.headline)).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(.app(.caption)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            Text(value)
                .font(.display(.title2))
                .foregroundStyle(Theme.primary)
        }
    }

    private func restart() {
        withAnimation(.snappy) {
            session = PlacementSession(seed: UInt64.random(in: 1...UInt64.max))
            picked = nil
            started = true
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(.headline))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.chunky)
        .controlSize(.large)
    }
}

/// Карточка с переворотом по вертикальной оси: лицевая сторона уходит,
/// оборотная выходит — как настоящую карточку переворачивают в руке.
struct FlipCard<Front: View, Back: View>: View {
    var flipped: Bool
    @ViewBuilder var front: () -> Front
    @ViewBuilder var back: () -> Back

    var body: some View {
        ZStack {
            face(front()).opacity(flipped ? 0 : 1)
            face(back())
                .opacity(flipped ? 1 : 0)
                // Оборот заранее развёрнут, чтобы после переворота текст
                // не читался зеркально.
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0),
                          perspective: 0.4)
        .animation(.spring(duration: 0.5, bounce: 0.2), value: flipped)
    }

    private func face<Content: View>(_ content: Content) -> some View {
        content
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 240)
            .panel(radius: 24)
    }
}
