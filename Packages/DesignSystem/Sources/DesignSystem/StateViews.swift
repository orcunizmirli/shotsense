import SwiftUI

/// Boş ve hata durumları için tek gösterim.
///
/// Her liste ekranı boş kalabileceği **tüm** sebepler için ayrı metin göstermek zorundadır
/// (02 §3): "izin yok" ile "sonuç yok" aynı ekranı gösterirse kullanıcı ne yapacağını bilemez.
public struct StateView: View {
    private let symbolName: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        symbolName: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbolName = symbolName
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Token.Space.lg) {
            Image(systemName: symbolName)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .scaleEffect(hasAppeared ? 1 : 0.85)
                .opacity(hasAppeared ? 1 : 0)

            VStack(spacing: Token.Space.sm) {
                Text(title)
                    .font(Token.Typography.title)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(Token.Typography.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(hasAppeared ? 1 : 0)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.prominentAction)
                    .frame(maxWidth: 280)
                    .opacity(hasAppeared ? 1 : 0)
            }
        }
        .padding(Token.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(
                Token.Motion.respectingReduceMotion(
                    Token.Motion.expressive, isReduced: reduceMotion
                )
            ) {
                hasAppeared = true
            }
        }
    }
}

/// Kitaplığın üstünde yüzen indeksleme rozeti.
///
/// Eskiden tam genişlikte bir banttı; bant içeriği aşağı iter ve **her ilerleme
/// güncellemesinde ızgarayı yeniden yerleştirir**. Yüzen rozet yerleşimin dışındadır:
/// güncellenmesi tek bir metnin yeniden çizilmesinden ibarettir.
public struct IndexingBadge: View {
    private let analyzed: Int
    private let total: Int

    public init(analyzed: Int, total: Int) {
        self.analyzed = analyzed
        self.total = total
    }

    public var body: some View {
        HStack(spacing: Token.Space.sm) {
            ProgressView(value: Double(analyzed), total: Double(max(total, 1)))
                .progressViewStyle(.circular)
                .controlSize(.mini)

            Text("\(analyzed) / \(total)")
                .font(Token.Typography.caption)
                .monospacedDigit()
                // Sayı değişimi kayarak geçer, zıplayarak değil.
                .contentTransition(.numericText(value: Double(analyzed)))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Token.Space.md)
        .padding(.vertical, Token.Space.sm)
        .floatingCapsule()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("İndeksleme sürüyor: \(analyzed) / \(total)")
    }
}

/// İçerik yüklenirken gösterilen iskelet hücre.
///
/// Boş ekran yerine iskelet göstermek algılanan bekleme süresini belirgin biçimde kısaltır;
/// ayrıca ızgaranın yüksekliği sabit kaldığı için içerik gelince zıplama olmaz.
public struct SkeletonCard: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            RoundedRectangle(cornerRadius: Token.Radius.md, style: .continuous)
                .fill(.surface)
                .aspectRatio(9 / 16, contentMode: .fit)

            VStack(alignment: .leading, spacing: Token.Space.xs) {
                Capsule().fill(.surface).frame(height: 9)
                Capsule().fill(.surface).frame(width: 44, height: 7)
            }
        }
        .shimmering()
        .accessibilityHidden(true)
    }
}

/// Kısa süreli geri bildirim balonu ("Hatırlatıcı oluşturuldu").
public struct ToastView: View {
    private let message: String
    private let symbolName: String

    public init(message: String, symbolName: String = "checkmark.circle.fill") {
        self.message = message
        self.symbolName = symbolName
    }

    public var body: some View {
        HStack(spacing: Token.Space.sm) {
            Image(systemName: symbolName)
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: message)
            Text(message)
                .font(Token.Typography.callout)
        }
        .padding(.horizontal, Token.Space.lg)
        .padding(.vertical, Token.Space.md)
        .floatingCapsule()
        .accessibilityAddTraits(.isStaticText)
    }
}
