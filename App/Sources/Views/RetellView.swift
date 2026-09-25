import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AJFMCore

/// Пересказ серии: наговариваешь, что понял, — получаешь разбор.
struct RetellView: View {
    @Environment(\.modelContext) private var context
    @State private var model: RetellFlowModel?
    @State private var showSubtitleImporter = false
    @State private var importResult: ImportResult?
    @Query(sort: \RetellSession.createdAt, order: .reverse) private var history: [RetellSession]

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(tr("Пересказ", "Reconto", "Retelling"))
        .onAppear {
            if model == nil { model = RetellFlowModel(context: context) }
        }
        .fileImporter(
            isPresented: $showSubtitleImporter,
            allowedContentTypes: [.plainText, .text, .data]
        ) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                model?.loadSubtitles(from: data)
            }
        }
        .alert(
            tr("Набор создан", "Baralho criado", "Deck created"),
            isPresented: Binding(
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } })
        ) {
            Button(CommonText.ok) { importResult = nil }
        } message: {
            if let importResult {
                Text("«\(importResult.deckName)»: \(Counted.words(importResult.addedNotes)).")
            }
        }
    }

    @ViewBuilder
    private func content(_ model: RetellFlowModel) -> some View {
        List {
            subtitleSection(model)

            switch model.step {
            case .needsSubtitles:
                EmptyView()
            case .ready:
                recordSection(model)
            case .recording:
                recordingSection(model)
            case .editingTranscript:
                transcriptSection(model)
            case .analyzing:
                Section {
                    ProgressView(tr("Разбираю пересказ…", "A analisar o reconto…",
                                    "Reviewing your retelling…"))
                }
            case .done:
                if let report = model.report {
                    reportSections(report, model: model)
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button(tr("Начать заново", "Recomeçar", "Start over")) { model.reset() }
                }
            }

            if !history.isEmpty {
                historySection
            }
        }
    }

    // MARK: - Шаги

    @ViewBuilder
    private func subtitleSection(_ model: RetellFlowModel) -> some View {
        Section {
            if let summary = model.subtitleSummary {
                LabeledContent(tr("Субтитры", "Legendas", "Subtitles"), value: summary)
                TextField(tr("Название серии", "Nome do episódio", "Episode name"), text: Binding(
                    get: { model.episodeTitle }, set: { model.episodeTitle = $0 }))
                if let track = model.track, track.duration > 60 {
                    VStack(alignment: .leading) {
                        Text(tr("Досмотрел до ", "Vi até ao minuto ", "Watched up to ")
                             + "\(Int(model.watchedUpToMinutes))"
                             + tr(" мин", "", " min"))
                            .font(.app(.callout))
                        Slider(
                            value: Binding(
                                get: { model.watchedUpToMinutes },
                                set: { model.watchedUpToMinutes = $0 }),
                            in: 1...(track.duration / 60).rounded(),
                            step: 1)
                    }
                }
            } else {
                Button(tr("Загрузить субтитры серии", "Carregar as legendas do episódio",
                          "Load the episode's subtitles"),
                       systemImage: "doc.text") {
                    showSubtitleImporter = true
                }
            }
        } header: {
            Text(tr("Серия", "Episódio", "Episode"))
        } footer: {
            Text(model.track == nil
                 ? tr("Субтитры обязательны. Без них модель судит о содержании по своим "
                        + "воспоминаниям о сериале и начинает сообщать об ошибках, которых "
                        + "не было — а доверие к разбору теряется с первого такого случая.",
                      "As legendas são obrigatórias. Sem elas, o modelo julga o conteúdo "
                        + "pelo que se lembra da série e aponta erros que não existiram — "
                        + "e a confiança na análise perde-se logo à primeira.",
                      "Subtitles are required. Without them the model judges the content "
                        + "from its memory of the show and reports mistakes that never "
                        + "happened — and trust in the review is gone after the first one.")
                 : tr("Разбор увидит субтитры только до отмеченной минуты — чтобы не "
                        + "проговориться о том, чего ты ещё не смотрел.",
                      "A análise só vê as legendas até ao minuto marcado — para não "
                        + "revelar o que ainda não viste.",
                      "The review only sees subtitles up to the marked minute — so it "
                        + "won't spoil what you haven't watched yet."))
        }
    }

    @ViewBuilder
    private func recordSection(_ model: RetellFlowModel) -> some View {
        Section {
            Button(tr("Начать пересказ", "Começar o reconto", "Start retelling"),
                   systemImage: "mic.circle.fill") {
                model.startRecording()
            }
            .buttonStyle(.borderedProminent)
        } footer: {
            Text(tr("Говори по-английски две-пять минут: о чём была серия, что случилось, "
                        + "что ты понял. Ошибки — это нормально, они и станут карточками.",
                    "Fala em inglês dois a cinco minutos: de que tratou o episódio, o que "
                        + "aconteceu, o que percebeste. Errar é normal — os erros viram cartões.",
                    "Speak English for two to five minutes: what the episode was about, what "
                        + "happened, what you understood. Mistakes are fine — they become cards."))
        }
    }

    @ViewBuilder
    private func recordingSection(_ model: RetellFlowModel) -> some View {
        Section {
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
                Text(timeString(model.recorder.elapsed))
                    .monospacedDigit()
                Spacer()
                Text(Counted.words(model.recorder.wordCount))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            if !model.recorder.fullText.isEmpty {
                Text(model.recorder.fullText)
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
            }
            Button(tr("Закончить", "Terminar", "Finish"), systemImage: "stop.circle.fill") {
                model.stopRecording()
            }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        } header: {
            Text(tr("Идёт запись", "A gravar", "Recording"))
        }
    }

    @ViewBuilder
    private func transcriptSection(_ model: RetellFlowModel) -> some View {
        Section {
            TextEditor(text: Binding(
                get: { model.transcript }, set: { model.transcript = $0 }))
                .frame(minHeight: 200)
                .font(.app(.callout))

            Button(tr("Разобрать", "Analisar", "Review"), systemImage: "sparkles") {
                Task { await model.analyze() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canAnalyze)

            LabeledContent(
                tr("Обойдётся примерно в", "Vai custar cerca de", "Will cost about"),
                value: String(format: "$%.3f", model.estimatedCost))
                .font(.app(.caption))
            Button(tr("Перезаписать", "Gravar de novo", "Record again")) { model.reset() }
                .font(.app(.caption))
        } header: {
            Text(tr("Расшифровка — поправь ошибки", "Transcrição — corrige os erros",
                    "Transcript — fix the mistakes"))
        } footer: {
            Text(tr("Распознавание путается на акценте. Если оставить «serious» там, где "
                        + "ты сказал «furious», разбор решит, что ты не понял сцену — "
                        + "и будет неправ. Пара минут правки того стоит.",
                    "O reconhecimento confunde-se com o sotaque. Se ficar «serious» onde "
                        + "disseste «furious», a análise vai achar que não percebeste a cena — "
                        + "e vai estar errada. Vale a pena corrigir dois minutos.",
                    "Recognition stumbles on accents. Leave “serious” where you said "
                        + "“furious” and the review will think you misunderstood the scene — "
                        + "and be wrong. A couple of minutes of fixing is worth it."))
        }
    }

    @ViewBuilder
    private func reportSections(_ report: RetellReport, model: RetellFlowModel) -> some View {
        Section {
            HStack {
                Text(tr("Понимание", "Compreensão", "Understanding"))
                Spacer()
                Text("\(report.understanding.coveragePercent)%")
                    .font(.app(.title3, weight: .bold))
            }
            ProgressView(value: report.understanding.coverage)
        } header: {
            Text(tr("Итог", "Resultado", "Result"))
        } footer: {
            Text(tr("Разбор стоил ", "A análise custou ", "The review cost ")
                 + String(format: "$%.3f", model.lastCost))
        }

        if !report.topPriorities.isEmpty {
            Section(tr("Над чем поработать", "No que trabalhar", "What to work on")) {
                ForEach(report.topPriorities, id: \.self) { item in
                    Label(item, systemImage: "target")
                }
            }
        }

        pointSection(tr("Понял верно", "Percebeste bem", "Understood correctly"),
                     report.understanding.correct, icon: "checkmark", color: .green)
        pointSection(tr("Понял неверно", "Percebeste mal", "Misunderstood"),
                     report.understanding.incorrect, icon: "xmark", color: .red)
        pointSection(tr("Упустил", "Escapou-te", "Missed"),
                     report.understanding.missed, icon: "eye.slash", color: .orange)

        if !report.language.grammar.isEmpty {
            Section(tr("Грамматика", "Gramática", "Grammar")) {
                ForEach(Array(report.language.grammar.enumerated()), id: \.offset) { item in
                    correctionRow(item.element)
                }
            }
        }

        if !report.language.vocabulary.isEmpty {
            Section(tr("Словарь", "Vocabulário", "Vocabulary")) {
                ForEach(Array(report.language.vocabulary.enumerated()), id: \.offset) { item in
                    correctionRow(item.element)
                }
            }
        }

        if let fluency = report.language.fluencyNote, !fluency.isEmpty {
            Section(tr("Беглость", "Fluência", "Fluency")) { Text(fluency) }
        }

        Section {
            Button(tr("Сделать карточки из ошибок", "Criar cartões com os erros",
                      "Turn mistakes into cards"),
                   systemImage: "rectangle.stack.badge.plus") {
                importResult = model.makeDeck()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.deckCandidateCount == 0)

            Button(tr("Новый пересказ", "Novo reconto", "New retelling")) { model.reset() }
        } footer: {
            Text(model.deckCandidateCount > 0
                 ? tr("Соберём ", "Vamos criar ", "We'll make ")
                    + Counted.cardsAccusative(model.deckCandidateCount)
                    + tr(": слова, которых не хватило, и повторяющиеся ошибки. Это и есть "
                            + "смысл всей затеи — пересказ превращается в то, что можно выучить.",
                         ": as palavras que faltaram e os erros repetidos. É esse o sentido "
                            + "de tudo — o reconto transforma-se em algo que se pode aprender.",
                         ": the words you were missing and the repeated mistakes. That's the "
                            + "whole point — a retelling turns into something you can learn.")
                 : tr("Ошибок не нашлось — делать карточки не из чего.",
                      "Não há erros — não há de que fazer cartões.",
                      "No mistakes found — nothing to make cards from."))
        }
    }

    @ViewBuilder
    private func pointSection(
        _ title: String, _ points: [RetellReport.Point], icon: String, color: Color
    ) -> some View {
        if !points.isEmpty {
            Section(title) {
                ForEach(Array(points.enumerated()), id: \.offset) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(item.element.claim, systemImage: icon)
                            .foregroundStyle(color)
                        if let quote = item.element.quote, !quote.isEmpty {
                            Text("«\(quote)»")
                                .font(.app(.caption))
                                .italic()
                                .foregroundStyle(.secondary)
                        }
                        if let comment = item.element.comment, !comment.isEmpty {
                            Text(comment).font(.app(.caption))
                        }
                        if item.element.mayBeMisheard == true {
                            Label(tr("возможно, ошибка распознавания",
                                     "talvez um erro de reconhecimento",
                                     "possibly a recognition error"),
                                  systemImage: "waveform.badge.exclamationmark")
                                .font(.app(.caption2))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func correctionRow(_ correction: RetellReport.Correction) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(correction.said).strikethrough().foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.app(.caption2))
                Text(correction.better).bold()
            }
            if let why = correction.why, !why.isEmpty {
                Text(why).font(.app(.caption)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section(tr("История", "Histórico", "History")) {
            ForEach(history) { session in
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.episodeTitle)
                    Text(tr("Понимание", "Compreensão", "Understanding")
                         + " \(Int(session.coverage * 100))% · "
                         + session.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(history[index]) }
                try? context.save()
            }
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        String(format: "%d:%02d", Int(interval) / 60, Int(interval) % 60)
    }
}
