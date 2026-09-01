import CoreGraphics
import SwiftUI

/// Çözülmüş bir `CGImage`'i gösterir.
///
/// **Bu görünüm çözme yapmaz.** Çözme, kaydırma sırasında hücre görünür olduğunda değil,
/// önceden (`ThumbnailStore`) yapılır. Hücrenin kendi içinde `.task { decode() }` çalıştıran
/// bir tasarım, hızlı kaydırmada onlarca eşzamanlı çözme görevi başlatır — kare düşmesinin
/// en yaygın sebebi budur.
///
/// `UIImage` yerine `CGImage`: `Image(decorative:scale:)` her platformda vardır ve
/// `DesignSystem` UIKit'siz kalır (R6).
public struct ThumbnailImage: View {
    private let image: CGImage?
    private let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(image: CGImage?, cornerRadius: CGFloat = Token.Radius.md) {
        self.image = image
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ZStack {
            // Yer tutucu her zaman altta durur: görsel gelince yerini "kaplar", böylece
            // yerleşim hiç değişmez ve ızgarada zıplama olmaz.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.surface)

            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    // Ani "pop" yerine yumuşak geçiş; premium hissin ucuz ama etkili parçası.
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(
            Token.Motion.respectingReduceMotion(Token.Motion.standard, isReduced: reduceMotion),
            value: image != nil
        )
    }
}

/// Ham veriden çözerek gösteren görünüm.
///
/// Yalnız **tek** görselin gösterildiği yerlerde kullanılır (detay ekranı, onboarding
/// örneği): orada eşzamanlı çözme sorunu yoktur ve ayrı bir önbellek katmanı fazladan
/// karmaşıklık olurdu.
public struct DecodedImage: View {
    private let data: Data?
    private let maxPixelSize: Int
    private let cornerRadius: CGFloat

    @State private var image: CGImage?

    public init(data: Data?, maxPixelSize: Int = 1600, cornerRadius: CGFloat = Token.Radius.lg) {
        self.data = data
        self.maxPixelSize = maxPixelSize
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ThumbnailImage(image: image, cornerRadius: cornerRadius)
            .task(id: data) {
                guard let data else {
                    image = nil
                    return
                }
                image = await ImageDecoding.decodeInBackground(data, maxPixelSize: maxPixelSize)
            }
    }
}
