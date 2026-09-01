import ShotCore
import SwiftUI

/// Kategorinin görsel kimliği: ad, SF Symbol ve renk.
///
/// **Neden `DesignSystem`'de:** ad ve ikon sunum bilgisidir; `ShotCore` bunları bilmez
/// (R5/R1). Böylece yerelleştirme ve ikon değişimi domain'e dokunmadan yapılır.
public struct CategoryStyle: Sendable {
    /// Görünen ad. `LocalizedStringKey` değil `String`: hem `Text` içinde hem
    /// erişilebilirlik etiketi birleştirmesinde kullanılıyor.
    public let title: String
    public let symbolName: String
    public let tint: Color

    public static func style(for category: ShotCategory) -> CategoryStyle {
        switch category {
        case .receipt:
            return .init(title: "Fiş", symbolName: "receipt", tint: .green)
        case .ticket:
            return .init(title: "Bilet", symbolName: "ticket", tint: .indigo)
        case .wifi:
            return .init(title: "Wi-Fi", symbolName: "wifi", tint: .teal)
        case .conversation:
            return .init(title: "Sohbet", symbolName: "bubble.left.and.bubble.right", tint: .blue)
        case .recipe:
            return .init(title: "Tarif", symbolName: "fork.knife", tint: .orange)
        case .article:
            return .init(title: "Makale", symbolName: "doc.text", tint: .brown)
        case .code:
            return .init(title: "Kod", symbolName: "chevron.left.forwardslash.chevron.right", tint: .purple)
        case .product:
            return .init(title: "Ürün", symbolName: "bag", tint: .pink)
        case .location:
            return .init(title: "Konum", symbolName: "mappin.and.ellipse", tint: .red)
        case .event:
            return .init(title: "Etkinlik", symbolName: "calendar", tint: .mint)
        case .banking:
            return .init(title: "Banka", symbolName: "banknote", tint: .cyan)
        case .shipping:
            return .init(title: "Kargo", symbolName: "shippingbox", tint: .yellow)
        case .identity:
            return .init(title: "Kimlik", symbolName: "person.text.rectangle", tint: .gray)
        case .other:
            return .init(title: "Diğer", symbolName: "square.grid.2x2", tint: .secondary)
        }
    }
}

/// Kategori rozeti.
///
/// Renk **tek başına** taşıyıcı değildir: her rozette ikon ve metin de vardır (02 §4).
/// Renk körlüğü olan kullanıcı da kategoriyi ayırt edebilmelidir.
public struct CategoryBadge: View {
    private let category: ShotCategory
    private let compact: Bool

    public init(category: ShotCategory, compact: Bool = false) {
        self.category = category
        self.compact = compact
    }

    public var body: some View {
        let style = CategoryStyle.style(for: category)
        HStack(spacing: Token.Space.xs) {
            Image(systemName: style.symbolName)
                .imageScale(.small)
            if !compact {
                Text(style.title)
                    .font(.caption.weight(.medium))
            }
        }
        .padding(.horizontal, compact ? Token.Space.xs : Token.Space.sm)
        .padding(.vertical, Token.Space.xs)
        .background(style.tint.opacity(0.18), in: Capsule())
        .foregroundStyle(style.tint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(style.title)
    }
}
