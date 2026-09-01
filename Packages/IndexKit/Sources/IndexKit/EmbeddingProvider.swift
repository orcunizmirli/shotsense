import AppFoundation
import Foundation
import NaturalLanguage

/// Cümle vektörü üretir; anlamsal aramanın ("kulaklık fişi" → "Bluetooth Kulaklık Sipariş
/// Özeti") kaynağıdır.
///
/// **Neden `NLEmbedding`:** Foundation Models embedding API'si sunmaz, `NaturalLanguage`
/// ise cihazda hazır, ücretsiz ve modelsiz cihazlarda zarifçe `nil` döner. Vektör yoksa
/// arama bozulmaz; hibrit skorda anlamsal bileşenin ağırlığı terim bileşenine devredilir.
///
/// **`Sendable` değildir — bilinçli.** `NLEmbedding` bir sınıf ve `Sendable` değil; onu
/// `@unchecked Sendable` ile sarmalamak, belgelenmemiş bir thread-safety varsayımını
/// derleyiciden gizlemek olurdu. Bunun yerine tip `HybridIndex` aktörünün **içinde**
/// yaşar: izolasyonu aktör sağlar, varsayıma gerek kalmaz.
public struct EmbeddingProvider {
    private let embeddings: [NLEmbedding]

    /// - Parameter languages: sırayla denenir; ilk yüklenebilen kullanılır.
    public init(languages: [NLLanguage] = [.turkish, .english]) {
        embeddings = languages.compactMap { NLEmbedding.sentenceEmbedding(for: $0) }
        if embeddings.isEmpty {
            Log.info(.search, "Cümle vektörü modeli yok; arama terim ağırlıklı çalışacak")
        }
    }

    public var isAvailable: Bool { !embeddings.isEmpty }

    /// Birim uzunluğa normalize edilmiş vektör.
    ///
    /// Normalizasyon indeksleme sırasında bir kez yapılır; böylece arama sırasında kosinüs
    /// benzerliği yalnız nokta çarpımına iner (her sorguda norm hesaplamak 5.000 belgede
    /// gereksiz iştir).
    public func vector(for text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for embedding in embeddings {
            guard let raw = embedding.vector(for: trimmed) else { continue }
            return Self.normalize(raw.map(Float.init))
        }
        return nil
    }

    static func normalize(_ vector: [Float]) -> [Float]? {
        let magnitude = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        guard magnitude > 0, magnitude.isFinite else { return nil }
        return vector.map { $0 / magnitude }
    }

    /// Normalize edilmiş iki vektörün kosinüs benzerliği (nokta çarpımı).
    /// Uzunlukları farklıysa karşılaştırma anlamsızdır ve 0 döner.
    public static func similarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var total: Float = 0
        for index in lhs.indices {
            total += lhs[index] * rhs[index]
        }
        // Sayısal yuvarlama benzerliği hafifçe aralık dışına taşırabilir.
        return Double(min(max(total, -1), 1))
    }
}
