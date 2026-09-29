import SwiftUI
import AJFMCore

/// Данные продавца из Info.plist — одни на документы, письмо в поддержку
/// и экран «О продавце». Те же значения указываются в App Store Connect
/// для закона ЕС о цифровых услугах (DSA).
enum LegalInfo {
    static var seller: LegalDocument.Seller {
        LegalDocument.Seller(name: value("RecapSellerName"),
                             address: value("RecapSellerAddress"),
                             email: value("RecapContactEmail"))
    }

    private static func value(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }

    /// Текст документа на языке приложения, с подставленными данными продавца.
    static func text(_ kind: LegalDocument.Kind) -> String? {
        let name = LegalDocument.resourceName(kind, language: Loc.language)
        guard let url = Bundle.main.url(forResource: name, withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return LegalDocument.fill(raw, seller: seller)
    }
}

/// Юридический документ прямо в приложении: читается без сети и всегда
/// совпадает с этой версией приложения.
struct LegalDocumentView: View {
    let kind: LegalDocument.Kind

    @State private var blocks: [LegalDocument.Block] = []
    @State private var text = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if blocks.isEmpty {
                    MascotSays(mood: .oops,
                               text: tr("Документ не нашёлся в этой сборке.",
                                        "O documento não foi encontrado nesta versão.",
                                        "The document is missing from this build."),
                               size: 64)
                }
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .padding()
            .textSelection(.enabled)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !text.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .onAppear {
            guard blocks.isEmpty, let loaded = LegalInfo.text(kind) else { return }
            text = loaded
            blocks = LegalDocument.parse(loaded)
        }
    }

    @ViewBuilder
    private func view(for block: LegalDocument.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(.app(headingStyle(level), weight: .heavy))
                .foregroundStyle(Theme.ink)
                .padding(.top, level <= 2 ? 10 : 4)
        case .paragraph(let text):
            inline(text).font(.app(.body)).foregroundStyle(Theme.ink)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(Theme.primary).font(.app(.body, weight: .heavy))
                inline(text).font(.app(.body)).foregroundStyle(Theme.ink)
            }
        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).").font(.app(.body, weight: .bold)).foregroundStyle(Theme.primary)
                inline(text).font(.app(.body)).foregroundStyle(Theme.ink)
            }
        case .table(let rows):
            table(rows)
        case .rule:
            Divider().padding(.vertical, 8)
        }
    }

    private func headingStyle(_ level: Int) -> Font.TextStyle {
        switch level {
        case ...1: return .title2
        case 2: return .title3
        default: return .headline
        }
    }

    /// Таблица на экране телефона не помещается — каждая строка становится
    /// карточкой «заголовок столбца: значение».
    @ViewBuilder
    private func table(_ rows: [[String]]) -> some View {
        let header = rows.first ?? []
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.dropFirst().enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                        if index == 0 {
                            inline(cell).font(.app(.callout, weight: .bold)).foregroundStyle(Theme.ink)
                        } else if !cell.isEmpty {
                            VStack(alignment: .leading, spacing: 1) {
                                if index < header.count {
                                    Text(header[index]).font(.app(.caption, weight: .bold))
                                        .foregroundStyle(Theme.muted)
                                }
                                inline(cell).font(.app(.callout)).foregroundStyle(Theme.ink)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel(lip: false, radius: 14)
            }
        }
    }

    /// Жирный, курсив и ссылки внутри строки.
    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(text)
    }
}

/// Кто продаёт приложение — то же, что Apple показывает в карточке
/// приложения в ЕС (DSA).
struct SellerInfoView: View {
    private let seller = LegalInfo.seller

    var body: some View {
        List {
            Section {
                row(tr("Продавец", "Vendedor", "Trader"), seller.name, symbol: "person.text.rectangle")
                row(tr("Адрес", "Morada", "Address"), seller.address, symbol: "mappin.and.ellipse")
                row("E-mail", seller.email, symbol: "envelope")
            } footer: {
                Text(tr("Приложение продаётся через App Store; оплату, возвраты и НДС ведёт Apple.",
                        "A aplicação é vendida através da App Store; pagamentos, reembolsos e IVA "
                            + "são geridos pela Apple.",
                        "The app is sold through the App Store; Apple handles payment, refunds and VAT."))
            }
        }
        .themedScreen()
        .navigationTitle(tr("О продавце", "Sobre o vendedor", "About the trader"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String, symbol: String) -> some View {
        LabeledContent {
            Text(LegalDocument.Seller.isPlaceholder(value)
                 ? tr("не заполнено", "por preencher", "not set") : value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}
