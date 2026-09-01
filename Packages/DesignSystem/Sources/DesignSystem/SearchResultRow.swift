import CoreGraphics
import ShotCore
import SwiftUI

/// Arama sonucu satırı.
///
/// Önizleme + başlık + eşleşme parçası birlikte gösterilir: kullanıcı sonucun **neden**
/// döndüğünü görmeden listeye güvenmez, tek tek açıp kontrol eder.
public struct SearchResultRow: View {
    private let result: SearchResult
    private let image: CGImage?

    public init(result: SearchResult, image: CGImage?) {
        self.result = result
        self.image = image
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Token.Space.md) {
            ThumbnailImage(image: image, cornerRadius: Token.Radius.sm)
                .frame(width: 54, height: 96)

            VStack(alignment: .leading, spacing: Token.Space.xs) {
                HStack(spacing: Token.Space.sm) {
                    CategoryBadge(category: result.shot.analysis.category)
                    Text(result.shot.createdAt, format: .dateTime.day().month(.abbreviated).year())
                        .font(Token.Typography.micro)
                        .foregroundStyle(.tertiary)
                }

                Text(title)
                    .font(Token.Typography.headline)
                    .lineLimit(2)

                if !result.snippet.isEmpty {
                    Text(result.snippet)
                        .font(Token.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !entitySummary.isEmpty {
                    // Çıkarılmış bilgiler satırda özetlenir: kullanıcı fişi açmadan
                    // tutarını görebiliyorsa arama gerçekten işe yaramış demektir.
                    Text(entitySummary)
                        .font(Token.Typography.micro)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.quaternary)
                .padding(.top, Token.Space.xl)
        }
        .padding(Token.Space.md)
        .surfaceCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var title: String {
        result.shot.analysis.title.isEmpty ? "Başlıksız" : result.shot.analysis.title
    }

    /// En fazla iki çıkarılmış değerin kısa özeti.
    private var entitySummary: String {
        result.shot.analysis.displayableEntities
            .filter { !$0.kind.isSensitive }
            .prefix(2)
            .map(\.rawValue)
            .joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        let category = CategoryStyle.style(for: result.shot.analysis.category).title
        let date = result.shot.createdAt.formatted(date: .abbreviated, time: .omitted)
        return "\(title), \(category), \(date). \(result.snippet)"
    }
}
