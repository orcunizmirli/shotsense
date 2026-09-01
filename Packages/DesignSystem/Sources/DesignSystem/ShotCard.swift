import ShotCore
import SwiftUI

/// Kitaplık ızgarasındaki tek hücre.
///
/// Yerleşim **sabit orandadır** (9:16): görsel gelmeden de yüksekliği bellidir, bu yüzden
/// içerik yüklendikçe ızgara zıplamaz. Değişken yükseklikli hücreler `LazyVGrid`'i her
/// yüklemede yeniden ölçmeye zorlar ve kaydırma takılır.
public struct ShotCard: View {
    private let shot: Shot
    private let image: CGImage?
    private let isSelected: Bool

    public init(shot: Shot, image: CGImage?, isSelected: Bool = false) {
        self.shot = shot
        self.image = image
        self.isSelected = isSelected
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            thumbnail
            caption
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var thumbnail: some View {
        ThumbnailImage(image: image, cornerRadius: Token.Radius.md)
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                CategoryBadge(category: shot.analysis.category, style: .glyph)
                    .padding(Token.Space.sm)
            }
            .overlay(alignment: .bottomTrailing) {
                if !shot.analysis.displayableEntities.isEmpty {
                    // Çıkarılmış bilgi taşıyan kayıtlar ızgarada göz taramasıyla ayırt
                    // edilebilmeli: kullanıcı "aksiyona çevrilebilir" olanları arıyor.
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.45), in: Circle())
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(Token.Space.sm)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Token.Radius.md, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(displayTitle)
                .font(Token.Typography.caption)
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)

            Text(shot.createdAt, format: .dateTime.day().month(.abbreviated))
                .font(Token.Typography.micro)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayTitle: String {
        shot.analysis.title.isEmpty ? "Başlıksız" : shot.analysis.title
    }

    /// VoiceOver etiketi başlık + kategori + tarihi birleştirir (02 §4): görme engelli
    /// kullanıcı ızgarada tek tek hücre dinlerken bu üçü olmadan seçim yapamaz.
    private var accessibilityLabel: String {
        let category = CategoryStyle.style(for: shot.analysis.category)
        let date = shot.createdAt.formatted(date: .abbreviated, time: .omitted)
        return "\(displayTitle), \(category.title), \(date)"
    }
}
