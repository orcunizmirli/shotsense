import CoreGraphics
import Foundation
import ImageIO

/// JPEG/PNG verisini görüntüleme boyutunda `CGImage`'e çözer.
///
/// **Neden hedef boyutta çözüyoruz:** 1290×2796'lık bir ekran görüntüsünü tam boyutta
/// çözmek ~14 MB bitmap üretir. Izgarada 30 hücre görünürken bu 400 MB'ı aşar ve sistem
/// uygulamayı sonlandırır. `kCGImageSourceThumbnailMaxPixelSize` ile ImageIO dosyayı
/// **akış hâlinde** okuyup yalnız hedef boyutu ayırır; ara tam boyutlu bitmap hiç oluşmaz.
public enum ImageDecoding {
    /// - Parameter maxPixelSize: uzun kenar. Ekran ölçeği çarpılmış piksel değeri verilmelidir.
    public static func decode(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Çözme anında yapılır, ilk çizimde değil: aksi hâlde kaydırma sırasında
            // ana iş parçacığı çözme için bloke olur ("lazy decode" takılması).
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Ana iş parçacığını bloke etmeden çözer.
    public static func decodeInBackground(_ data: Data, maxPixelSize: Int) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            decode(data, maxPixelSize: maxPixelSize)
        }.value
    }
}
