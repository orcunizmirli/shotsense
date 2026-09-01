import AppFoundation
import Foundation
import ShotCore
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

// dependency-lint:allow R6 — UIPasteboard'un SwiftUI karşılığı yok; süre sınırlı pano
// girdisi (07 §4) yalnız bu API ile kurulabilir. Muafiyet bu dosyayla sınırlıdır.

/// `ClipboardWriting` portunun sistem gerçeklemesi.
///
/// Hassas değerler panoda **süresiz kalmaz** (07 §4): IBAN veya wifi şifresi kopyalayan
/// kullanıcı bunu bir kez yapıştırır; panoda kalması diğer uygulamaların (ve pano
/// geçmişinin) erişimine açık bırakır.
///
/// > Not: bu, `UIKit` import eden **tek** dosyadır. Panoya yazmanın SwiftUI karşılığı yoktur
/// > ve süre sınırlı pano girdisi yalnız `UIPasteboard.setItems(_:options:)` ile kurulabilir.
/// > Bu yüzden R6'dan açık, gerekçeli ve tek dosyalık bir muafiyet alınır (dosya başındaki
/// > `dependency-lint:allow` satırı).
public struct SystemClipboard: ClipboardWriting {
    /// Hassas değerin panoda kalma süresi.
    private let sensitiveLifetime: TimeInterval

    public init(sensitiveLifetime: TimeInterval = 60) {
        self.sensitiveLifetime = sensitiveLifetime
    }

    public func copy(_ text: String, isSensitive: Bool) {
        #if canImport(UIKit)
        if isSensitive {
            UIPasteboard.general.setItems(
                [[UTType.utf8PlainText.identifier: text]],
                options: [.expirationDate: Date().addingTimeInterval(sensitiveLifetime)]
            )
        } else {
            UIPasteboard.general.string = text
        }
        #endif
        Log.debug(.action, "Panoya kopyalandı", detail: Redaction.summarize(text))
    }
}
