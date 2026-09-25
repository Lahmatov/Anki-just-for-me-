import SwiftUI
import AJFMCore

/// Запись и разбор одной попытки произношения.
struct PronunciationRecorderView: View {
    let word: String
    var pair: MinimalPair?
    var onResult: ((PronunciationAssessment) -> Void)?

    @State private var service = PronunciationService()
    @State private var permissionDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls

            if service.isRecording, !service.partialText.isEmpty {
                Text(service.partialText)
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
            }

            switch service.status {
            case .finished(let assessment):
                resultView(assessment)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.app(.callout))
                    .foregroundStyle(.orange)
            case .processing:
                ProgressView("Разбираю…")
            default:
                EmptyView()
            }

            if permissionDenied {
                Text("Нужны разрешения на микрофон и распознавание речи — "
                     + "их можно включить в настройках iOS.")
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
            }
        }
        .onChange(of: statusKey) { _, _ in
            if case .finished(let assessment) = service.status {
                onResult?(assessment)
            }
        }
        .onChange(of: word) { _, _ in
            // Иначе на новом слове висел бы разбор предыдущего.
            service.reset()
            permissionDenied = false
        }
    }

    /// Для onChange нужен сравнимый ключ — само состояние содержит структуру.
    private var statusKey: String {
        switch service.status {
        case .idle: return "idle"
        case .recording: return "recording"
        case .processing: return "processing"
        case .finished(let assessment): return "finished-\(assessment.recognized)"
        case .failed(let message): return "failed-\(message)"
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            SpeakButton(text: word, label: "Эталон")

            if service.isRecording {
                Button("Стоп", systemImage: "stop.circle.fill") { service.stop() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            } else {
                Button("Записать", systemImage: "mic.circle.fill") { record() }
                    .buttonStyle(.borderedProminent)
            }

            if service.hasRecording, !service.isRecording {
                Button("Я", systemImage: "play.circle") { service.playRecording() }
                    .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func resultView(_ assessment: PronunciationAssessment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title(for: assessment), systemImage: icon(for: assessment))
                .font(.app(.headline))
                .foregroundStyle(color(for: assessment))

            Text(assessment.message)
                .font(.app(.callout))
                .foregroundStyle(.secondary)

            if assessment.confidence > 0 {
                Text("Уверенность распознавателя: \(Int(assessment.confidence * 100))%")
                    .font(.app(.caption2))
                    .foregroundStyle(.tertiary)
            }

            if pair == nil {
                // Без этой оговорки экран обманывает: совпадение слова
                // не означает правильного произношения.
                Text(PronunciationEvaluator.onDeviceDisclaimer)
                    .font(.app(.caption2))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Button("Ещё раз", systemImage: "arrow.clockwise") { record() }
                    .buttonStyle(.bordered)
                if service.hasRecording {
                    Button("Сравнить с эталоном", systemImage: "waveform") {
                        service.playRecording()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.app(.caption))
        }
    }

    private func title(for assessment: PronunciationAssessment) -> String {
        switch assessment.verdict {
        // Формулировки намеренно сдержанные: «Отлично!» здесь было бы враньём.
        case .matched: return assessment.isReliable ? "Слово узнано" : "Похоже на нужное слово"
        case .mismatched: return "Прозвучало другое слово"
        case .unclear: return "Не разобрал"
        }
    }

    private func icon(for assessment: PronunciationAssessment) -> String {
        switch assessment.verdict {
        case .matched: return "checkmark.circle"
        case .mismatched: return "arrow.triangle.branch"
        case .unclear: return "questionmark.circle"
        }
    }

    private func color(for assessment: PronunciationAssessment) -> Color {
        switch assessment.verdict {
        case .matched: return assessment.isReliable ? .green : .yellow
        case .mismatched: return .orange
        case .unclear: return .secondary
        }
    }

    private func record() {
        Task {
            guard await PronunciationService.requestPermissions() else {
                permissionDenied = true
                return
            }
            permissionDenied = false
            service.reset()
            service.start(expecting: word, pair: pair)
        }
    }
}
