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
            return .init(
                title: "Kod",
                symbolName: "chevron.left.forwardslash.chevron.right",
                tint: .purple
            )
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
/// Renk **tek başına** taşıyıcı değildir: her varyantta ikon vardır ve erişilebilirlik
/// etiketi adı okur (02 §4). Renk körlüğü olan kullanıcı da kategoriyi ayırt edebilmelidir.
public struct CategoryBadge: View {
    public enum Style {
        /// Ad + ikon. Detay ve arama sonuçlarında.
        case full
        /// Yalnız ikon, küçük daire. Izgara hücresinde — başlık için yer kalsın diye.
        case glyph
    }

    private let category: ShotCategory
    private let style: Style

    public init(category: ShotCategory, style: Style = .full) {
        self.category = category
        self.style = style
    }

    public var body: some View {
        let categoryStyle = CategoryStyle.style(for: category)

        Group {
            switch style {
            case .full:
                HStack(spacing: Token.Space.xs) {
                    Image(systemName: categoryStyle.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                    Text(categoryStyle.title)
                        .font(Token.Typography.micro)
                }
                .padding(.horizontal, Token.Space.sm)
                .padding(.vertical, 5)
                .background(categoryStyle.tint.opacity(0.16), in: Capsule(style: .continuous))
                .foregroundStyle(categoryStyle.tint)

            case .glyph:
                Image(systemName: categoryStyle.symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    // Görselin üstünde durduğu için sabit renk yetmez: koyu zemin +
                    // ince materyal her arka planda okunurluğu garantiler.
                    .background(categoryStyle.tint.opacity(0.9), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(categoryStyle.title)
    }
}
