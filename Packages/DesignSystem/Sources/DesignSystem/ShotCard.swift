import ShotCore
import SwiftUI

/// Kitaplık ızgarasındaki tek hücre.
public struct ShotCard: View {
    private let shot: Shot
    private let thumbnailData: Data?

    public init(shot: Shot, thumbnailData: Data?) {
        self.shot = shot
        self.thumbnailData = thumbnailData
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.xs) {
            ThumbnailImage(data: thumbnailData)
                .aspectRatio(9 / 16, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    CategoryBadge(category: shot.analysis.category, compact: true)
                        .padding(Token.Space.xs)
                }
                .overlay(alignment: .bottomTrailing) {
                    if !shot.analysis.displayableEntities.isEmpty {
                        // Çıkarılmış bilgi taşıyan kayıtlar ızgarada ayırt edilebilmeli;
                        // kullanıcı "aksiyona çevrilebilir" olanları gözle tarayabiliyor.
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .padding(Token.Space.xs)
                            .background(.thinMaterial, in: Circle())
                            .padding(Token.Space.xs)
                    }
                }

            Text(displayTitle)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)

            Text(shot.createdAt, format: .dateTime.day().month(.abbreviated))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
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
