import CoreGraphics
import ImageIO
import SwiftUI

/// JPEG verisinden önizleme gösterir.
///
/// **Neden `UIImage` değil:** SwiftUI'nin `Image(decorative:scale:)` başlatıcısı `CGImage`
/// alır ve her platformda vardır. ImageIO ile çözerek `UIKit` bağımlılığından kaçınırız —
/// böylece `DesignSystem` macOS'ta da derlenir ve testleri simülatörsüz koşar (R6).
///
/// Çözme **arka planda** yapılır: ızgarada 60 hücre kaydırılırken ana iş parçacığında
/// JPEG çözmek gözle görülür takılma yaratır.
public struct ThumbnailImage: View {
    private let data: Data?
    private let cornerRadius: CGFloat

    @State private var image: CGImage?

    public init(data: Data?, cornerRadius: CGFloat = Token.Radius.md) {
        self.data = data
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.surface)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: data) {
            image = await Self.decode(data)
        }
    }

    private static func decode(_ data: Data?) async -> CGImage? {
        guard let data, !data.isEmpty else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }.value
    }
}
