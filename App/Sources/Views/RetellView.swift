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
        .navigationTitle("Пересказ")
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
            "Набор создан",
            isPresented: Binding(
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } })
        ) {
            Button("Хорошо") { importResult = nil }
        } message: {
            if let importResult {
                Text("«\(importResult.deckName)»: \(RussianPlural.words(importResult.addedNotes)).")
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
                Section { ProgressView("Разбираю пересказ…") }
            case .done:
                if let report = model.report {
                    reportSections(report, model: model)
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Начать заново") { model.reset() }
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
                LabeledContent("Субтитры", value: summary)
                TextField("Название серии", text: Binding(
                    get: { model.episodeTitle }, set: { model.episodeTitle = $0 }))
                if let track = model.track, track.duration > 60 {
                    VStack(alignment: .leading) {
                        Text("Досмотрел до \(Int(model.watchedUpToMinutes)) мин")
                            .font(.callout)
                        Slider(
                            value: Binding(
                                get: { model.watchedUpToMinutes },
                                set: { model.watchedUpToMinutes = $0 }),
                            in: 1...(track.duration / 60).rounded(),
                            step: 1)
                    }
                }
            } else {
                Button("Загрузить субтитры серии", systemImage: "doc.text") {
                    showSubtitleImporter = true
                }
            }
        } header: {
            Text("Серия")
        } footer: {
            Text(model.track == nil
                 ? "Субтитры обязательны. Без них модель судит о содержании по своим "
                   + "воспоминаниям о сериале и начинает сообщать об ошибках, которых "
                   + "не было — а доверие к разбору теряется с первого такого случая."
                 : "Разбор увидит субтитры только до отмеченной минуты — чтобы не "
                   + "проговориться о том, чего ты ещё не смотрел.")
        }
    }

    @ViewBuilder
    private func recordSection(_ model: RetellFlowModel) -> some View {
        Section {
            Button("Начать пересказ", systemImage: "mic.circle.fill") {
                model.startRecording()
            }
            .buttonStyle(.borderedProminent)
        } footer: {
            Text("Говори по-английски две-пять минут: о чём была серия, что случилось, "
                 + "что ты понял. Ошибки — это нормально, они и станут карточками.")
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
                Text(RussianPlural.words(model.recorder.wordCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !model.recorder.fullText.isEmpty {
                Text(model.recorder.fullText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Закончить", systemImage: "stop.circle.fill") { model.stopRecording() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        } header: {
            Text("Идёт запись")
        }
    }

    @ViewBuilder
    private func transcriptSection(_ model: RetellFlowModel) -> some View {
        Section {
            TextEditor(text: Binding(
                get: { model.transcript }, set: { model.transcript = $0 }))
                .frame(minHeight: 200)
                .font(.callout)

            Button("Разобрать", systemImage: "sparkles") {
                Task { await model.analyze() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canAnalyze)

            LabeledContent(
                "Обойдётся примерно в",
                value: String(format: "$%.3f", model.estimatedCost))
                .font(.caption)
            Button("Перезаписать") { model.reset() }
                .font(.caption)
        } header: {
            Text("Расшифровка — поправь ошибки")
        } footer: {
            Text("Распознавание путается на акценте. Если оставить «serious» там, где "
                 + "ты сказал «furious», разбор решит, что ты не понял сцену — "
                 + "и будет неправ. Пара минут правки того стоит.")
        }
    }

    @ViewBuilder
    private func reportSections(_ report: RetellReport, model: RetellFlowModel) -> some View {
        Section {
            HStack {
                Text("Понимание")
                Spacer()
                Text("\(report.understanding.coveragePercent)%")
                    .font(.title3).bold()
            }
            ProgressView(value: report.understanding.coverage)
        } header: {
            Text("Итог")
        } footer: {
            Text(String(format: "Разбор стоил $%.3f", model.lastCost))
        }

        if !report.topPriorities.isEmpty {
            Section("Над чем поработать") {
                ForEach(report.topPriorities, id: \.self) { item in
                    Label(item, systemImage: "target")
                }
            }
        }

        pointSection("Понял верно", report.understanding.correct, icon: "checkmark", color: .green)
        pointSection("Понял неверно", report.understanding.incorrect, icon: "xmark", color: .red)
        pointSection("Упустил", report.understanding.missed, icon: "eye.slash", color: .orange)

        if !report.language.grammar.isEmpty {
            Section("Грамматика") {
                ForEach(Array(report.language.grammar.enumerated()), id: \.offset) { item in
                    correctionRow(item.element)
                }
            }
        }

        if !report.language.vocabulary.isEmpty {
            Section("Словарь") {
                ForEach(Array(report.language.vocabulary.enumerated()), id: \.offset) { item in
                    correctionRow(item.element)
                }
            }
        }

        if let fluency = report.language.fluencyNote, !fluency.isEmpty {
            Section("Беглость") { Text(fluency) }
        }

        Section {
            Button("Сделать карточки из ошибок", systemImage: "rectangle.stack.badge.plus") {
                importResult = model.makeDeck()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.deckCandidateCount == 0)

            Button("Новый пересказ") { model.reset() }
        } footer: {
            Text(model.deckCandidateCount > 0
                 ? "Соберём \(RussianPlural.cardsAccusative(model.deckCandidateCount)): слова, которых не хватило, "
                   + "и повторяющиеся ошибки. Это и есть смысл всей затеи — пересказ "
                   + "превращается в то, что можно выучить."
                 : "Ошибок не нашлось — делать карточки не из чего.")
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
                                .font(.caption)
                                .italic()
                                .foregroundStyle(.secondary)
                        }
                        if let comment = item.element.comment, !comment.isEmpty {
                            Text(comment).font(.caption)
                        }
                        if item.element.mayBeMisheard == true {
                            Label("возможно, ошибка распознавания", systemImage: "waveform.badge.exclamationmark")
                                .font(.caption2)
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
                Image(systemName: "arrow.right").font(.caption2)
                Text(correction.better).bold()
            }
            if let why = correction.why, !why.isEmpty {
                Text(why).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section("История") {
            ForEach(history) { session in
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.episodeTitle)
                    Text("Понимание \(Int(session.coverage * 100))% · "
                         + session.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
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
