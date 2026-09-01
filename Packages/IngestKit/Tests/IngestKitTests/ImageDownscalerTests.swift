import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import IngestKit

@Suite("ImageDownscaler")
struct ImageDownscalerTests {
    /// Testin gerçek bir görsel üzerinde koşması için belleğe düz renkli bir PNG üretir.
    private func makePNG(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        return (
            try #require(properties[kCGImagePropertyPixelWidth] as? Int),
            try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        )
    }

    @Test("Uzun kenar hedef boyuta indirilir, en-boy oranı korunur")
    func downscalesLongestEdge() throws {
        // iPhone ekran görüntüsü oranına yakın bir kaynak.
        let source = try makePNG(width: 1290, height: 2796)
        let result = try ImageDownscaler.downscaledJPEG(from: source, maxPixelSize: 320)

        let size = try pixelSize(of: result)
        #expect(max(size.width, size.height) == 320)
        // 1290/2796 ≈ 0.461 → 320 yükseklikte genişlik ~148 olmalı.
        #expect(abs(Double(size.width) / Double(size.height) - 1290.0 / 2796.0) < 0.02)
    }

    @Test("Küçültülmüş çıktı kaynaktan belirgin biçimde küçüktür")
    func outputIsSmaller() throws {
        let source = try makePNG(width: 1290, height: 2796)
        let result = try ImageDownscaler.downscaledJPEG(from: source, maxPixelSize: 320)
        #expect(result.count < source.count)
    }

    @Test("Bozuk veri okunamaz hatası verir")
    func rejectsCorruptData() {
        #expect(throws: ImageDownscaler.Failure.self) {
            try ImageDownscaler.downscaledJPEG(
                from: Data("bu bir görsel değil".utf8), maxPixelSize: 320
            )
        }
    }

    @Test("Boyut sabitleri makul aralıkta")
    func sizeConstantsAreSane() {
        // Analiz boyutu OCR doğruluğu ile bellek arasındaki denge noktası (03 §7).
        #expect(ImageSize.analysis > ImageSize.thumbnail)
        #expect(ImageSize.thumbnail >= 240)
    }
}
