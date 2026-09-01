import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Görselleri analiz ve önizleme için küçültür.
///
/// **Neden ImageIO, `UIImage` değil:** `UIImage` yolu tüm görseli belleğe açar; 5.000
/// ekran görüntüsünü sırayla işlerken bu tek başına bellek baskısı yaratır. ImageIO'nun
/// thumbnail üreticisi ise dosyayı akış hâlinde okur ve yalnız hedef boyutu ayırır.
/// Ayrıca `UIKit` bağımlılığı olmadığı için paket macOS'ta da derlenir ve testleri
/// simülatörsüz koşar.
public enum ImageDownscaler {
    public enum Failure: Error {
        case unreadableSource
        case thumbnailCreationFailed
        case encodingFailed
    }

    /// Uzun kenarı `maxPixelSize`'a indirilmiş JPEG verisi üretir.
    ///
    /// - Parameter compressionQuality: 0.7 gözle fark edilmeyen ama boyutu ~3x düşüren nokta;
    ///   OCR zaten küçültülmüş görselde değil, orijinalinde koşar (bu çıktı önizleme içindir).
    public static func downscaledJPEG(
        from data: Data,
        maxPixelSize: Int,
        compressionQuality: Double = 0.7
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw Failure.unreadableSource
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            throw Failure.thumbnailCreationFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw Failure.encodingFailed
        }
        CGImageDestinationAddImage(
            destination,
            thumbnail,
            [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }
        return output as Data
    }
}

/// Boyut sabitleri tek yerde tutulur: pipeline, önizleme ve depolama bütçesi (03 §7) bunlara bağlı.
public enum ImageSize {
    /// OCR'a giren görselin uzun kenarı. Daha büyüğü tanıma doğruluğunu artırmaz ama
    /// Vision'ın bellek kullanımını doğrusal büyütür.
    public static let analysis = 2048
    /// Kitaplık ızgarasındaki önizleme. 3 sütunlu ızgarada 3x ekran ölçeğinde yeter.
    public static let thumbnail = 320
}
