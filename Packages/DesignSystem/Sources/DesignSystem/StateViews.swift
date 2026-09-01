import SwiftUI

/// Boş ve hata durumları için tek gösterim.
///
/// Her liste ekranı boş kalabileceği **tüm** sebepler için ayrı metin göstermek zorundadır
/// (02 §3): "izin yok" ile "sonuç yok" aynı ekranı gösterirse kullanıcı ne yapacağını bilemez.
public struct StateView: View {
    private let symbolName: String
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey
    private let actionTitle: LocalizedStringKey?
    private let action: (() -> Void)?

    public init(
        symbolName: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbolName = symbolName
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbolName)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: Token.minimumTapTarget)
            }
        }
    }
}

/// Kitaplığın üstünde görünen indeksleme ilerleme bandı.
public struct ProgressBanner: View {
    private let analyzed: Int
    private let total: Int

    public init(analyzed: Int, total: Int) {
        self.analyzed = analyzed
        self.total = total
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.xs) {
            Text("\(analyzed) / \(total) analiz edildi")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(analyzed), total: Double(max(total, 1)))
                .progressViewStyle(.linear)
        }
        .padding(.horizontal, Token.Space.lg)
        .padding(.vertical, Token.Space.sm)
        .background(.surface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("İndeksleme sürüyor: \(analyzed) / \(total)")
    }
}

/// İçerik yüklenirken gösterilen iskelet hücre.
///
/// Boş ekran yerine iskelet göstermek algılanan bekleme süresini belirgin biçimde kısaltır;
/// ayrıca ızgaranın yüksekliği sabit kaldığı için içerik gelince zıplama olmaz.
public struct SkeletonCard: View {
    @State private var isAnimating = false

    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: Token.Radius.md)
            .fill(.surface)
            .aspectRatio(9 / 16, contentMode: .fit)
            .opacity(isAnimating ? 0.5 : 1)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
            .accessibilityHidden(true)
    }
}
