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
                Picker("Уровень", selection: $minimumLevel) {
                    Text("Всё").tag(LogLevel.debug)
                    Text("События").tag(LogLevel.info)
                    Text("Проблемы").tag(LogLevel.warning)
                }
                .pickerStyle(.segmented)

                Picker("Раздел", selection: $category) {
                    Text("Все разделы").tag(LogCategory?.none)
                    ForEach(LogCategory.allCases, id: \.self) { item in
                        Text(item.title).tag(LogCategory?.some(item))
                    }
                }
            }

            if entries.isEmpty {
                ContentUnavailableView(
                    "Пока пусто",
                    systemImage: "text.alignleft",
                    description: Text("События появятся по мере работы с приложением."))
            } else {
                Section("Записей: \(entries.count)") {
                    ForEach(entries) { entry in
                        LogRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle("Журнал")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Поделиться журналом", systemImage: "square.and.arrow.up") {
                        share()
                    }
                    Button("Обновить", systemImage: "arrow.clockwise") {
                        refreshToken = UUID()
                    }
                    Divider()
                    Button("Очистить", systemImage: "trash", role: .destructive) {
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
                    .font(.caption)
                Text(entry.message)
                    .font(.callout)
                Spacer()
                Text(entry.date, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                Text(entry.category.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if entry.detail != nil, !expanded {
                    Text("подробнее")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if expanded, let detail = entry.detail {
                Text(detail)
                    .font(.caption)
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
