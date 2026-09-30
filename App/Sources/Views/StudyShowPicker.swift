import SwiftUI
import SwiftData
import AJFMCore

/// Выбор сериала, который учим: мои сериалы и готовые из каталога.
///
/// Сериал из каталога сразу получает слова первой серии — карта не будет
/// пустой. Отслеживаемый сериал без готовых слов тоже можно выбрать: слова
/// к серии подберутся с карты.
struct StudyShowPicker: View {
    /// Внутри знакомства лист не нужен — выбор идёт прямо на шаге.
    var embedded = false
    var onPick: ((String) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TrackedShow.addedAt, order: .reverse) private var tracked: [TrackedShow]
    @AppStorage(SettingsKey.studyShow) private var current: String?
    @State private var catalog: [CatalogIndexEntry] = []
    @State private var error: String?

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                ScrollView { content.padding() }
                    .background(Theme.background.ignoresSafeArea())
                    .navigationTitle(tr("Какой сериал учим?", "Que série estudamos?", "Which show?"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(CommonText.close) { dismiss() }
                        }
                    }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error {
                MascotSays(mood: .oops, text: error, size: 60)
            }
            if !tracked.isEmpty {
                CardSectionHeader(title: tr("Мои сериалы", "As minhas séries", "My shows"))
                ForEach(tracked) { show in
                    row(name: show.name, subtitle: Counted.episodes(show.episodes.count),
                        poster: show.posterURL) { pick(show.name, catalog: nil) }
                }
            }
            CardSectionHeader(title: tr("С готовыми словами", "Com palavras prontas", "With ready words"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                ForEach(catalog) { entry in
                    Button {
                        pick(entry.name, catalog: entry)
                    } label: {
                        CatalogTile(entry: entry)
                            .overlay(alignment: .topTrailing) {
                                if isCurrent(entry.name) { checkmark.offset(x: 6, y: -6) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("studyShow.\(entry.rank)")
                }
            }
        }
        .onAppear {
            if catalog.isEmpty { catalog = LocalCatalog.index()?.shows ?? [] }
        }
    }

    private func row(name: String, subtitle: String, poster: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let url = poster.flatMap(URL.init(string:)) {
                    CoverImage(url: url, width: 40)
                } else {
                    IconBadge(systemName: "tv", color: Theme.blue, size: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.app(.body, weight: .bold)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.app(.caption)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if isCurrent(name) { checkmark }
            }
            .padding(12)
            .panel()
        }
        .buttonStyle(.plain)
    }

    private var checkmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(Theme.green)
            .background(Circle().fill(Theme.surface))
    }

    private func isCurrent(_ name: String) -> Bool {
        current?.lowercased() == name.lowercased()
    }

    private func pick(_ name: String, catalog entry: CatalogIndexEntry?) {
        do {
            if let entry {
                try StudyShow.start(catalog: entry, in: context)
            } else {
                StudyShow.choose(name)
            }
            Haptics.success()
            onPick?(name)
            if !embedded { dismiss() }
        } catch {
            Log.failure(.importing, "Сериал для учёбы не выбрался", error)
            self.error = error.localizedDescription
        }
    }
}

/// «Учу этот сериал»: делает сериал главным — по нему строится карта.
struct StudyThisShowButton: View {
    let name: String
    var onChoose: (() -> Void)?
    @AppStorage(SettingsKey.studyShow) private var current: String?

    var body: some View {
        if current?.lowercased() == name.lowercased() {
            Label(tr("Учу этот сериал — он на карте", "Estou a estudar esta série — está no mapa",
                     "Studying this show — it's on the map"),
                  systemImage: "map.fill")
                .font(.app(.callout, weight: .bold))
                .foregroundStyle(Theme.green)
        } else {
            Button {
                Haptics.tap()
                if let onChoose { onChoose() } else { StudyShow.choose(name) }
            } label: {
                Label(tr("Учить этот сериал", "Estudar esta série", "Study this show"), systemImage: "map")
                    .font(.app(.callout, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.chunkySecondary)
            .accessibilityIdentifier("studyThisShow")
        }
    }
}
