import SwiftUI
import AJFMCore

/// Журнал событий прямо в приложении.
///
/// Консоль Xcode доступна только у Mac, поэтому понять, что пошло не так
/// на телефоне, можно только отсюда. Кнопка «Поделиться» отдаёт журнал
/// текстом — его можно переслать целиком.
struct LogView: View {
    @State private var minimumLevel: LogLevel = .debug
    @State private var category: LogCategory?
    @State private var exportedFile: ExportedFile?
    @State private var refreshToken = UUID()

    private var entries: [LogEntry] {
        _ = refreshToken
        return EventLog.shared.recent(minimumLevel: minimumLevel, category: category)
    }

    var body: some View {
        List {
            Section {
                Picker(tr("Уровень", "Nível", "Level"), selection: $minimumLevel) {
                    Text(tr("Всё", "Tudo", "Everything")).tag(LogLevel.debug)
                    Text(tr("События", "Eventos", "Events")).tag(LogLevel.info)
                    Text(tr("Проблемы", "Problemas", "Problems")).tag(LogLevel.warning)
                }
                .pickerStyle(.segmented)

                Picker(tr("Раздел", "Secção", "Section"), selection: $category) {
                    Text(tr("Все разделы", "Todas as secções", "All sections")).tag(LogCategory?.none)
                    ForEach(LogCategory.allCases, id: \.self) { item in
                        Text(item.title).tag(LogCategory?.some(item))
                    }
                }
            }

            if entries.isEmpty {
                ContentUnavailableView(
                    tr("Пока пусто", "Ainda vazio", "Nothing yet"),
                    systemImage: "text.alignleft",
                    description: Text(tr("События появятся по мере работы с приложением.",
                                         "Os eventos aparecem à medida que usas a aplicação.",
                                         "Events will show up as you use the app.")))
            } else {
                Section(tr("Записей: ", "Registos: ", "Entries: ") + "\(entries.count)") {
                    ForEach(entries) { entry in
                        LogRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle(tr("Журнал", "Registo", "Log"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(tr("Поделиться журналом", "Partilhar o registo", "Share the log"),
                           systemImage: "square.and.arrow.up") {
                        share()
                    }
                    Button(tr("Обновить", "Atualizar", "Refresh"), systemImage: "arrow.clockwise") {
                        refreshToken = UUID()
                    }
                    Divider()
                    Button(tr("Очистить", "Limpar", "Clear"), systemImage: "trash", role: .destructive) {
                        EventLog.shared.clear()
                        refreshToken = UUID()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $exportedFile) { file in
            ShareSheet(url: file.url)
        }
    }

    private func share() {
        let text = EventLog.shared.exportText(minimumLevel: minimumLevel)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ajfm-log.txt")
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else {
            return
        }
        exportedFile = ExportedFile(url: url)
    }
}

struct LogRow: View {
    let entry: LogEntry
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: entry.level.symbol)
                    .foregroundStyle(color)
                    .font(.app(.caption))
                Text(entry.message)
                    .font(.app(.callout))
                Spacer()
                Text(entry.date, format: .dateTime.hour().minute().second())
                    .font(.app(.caption2))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                Text(entry.category.title)
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                if entry.detail != nil, !expanded {
                    Text(tr("подробнее", "mais", "more"))
                        .font(.app(.caption2))
                        .foregroundStyle(.tertiary)
                }
            }

            if expanded, let detail = entry.detail {
                Text(detail)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.detail != nil { expanded.toggle() }
        }
    }

    private var color: Color {
        switch entry.level {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
