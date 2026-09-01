import Foundation
import ShotCore

/// Bellek-içi BM25 tam metin indeksi.
///
/// **Neden elle yazıldı:** SwiftData'nın tam metin araması yok, Core Data'nın `CONTAINS`
/// karşılaştırması ise sıralama üretmez — 4.000 sonuçtan hangisinin en alakalı olduğunu
/// söyleyemez. BM25 terim sıklığını, belge uzunluğunu ve terimin nadirliğini birlikte
/// tarttığı için "kulaklık" araması, kelimeyi bir kez geçen 200 sayfalık makale yerine
/// kelimeyi başlığında taşıyan ürün ekranını öne çıkarır.
///
/// Yapı tamamen saftır (Foundation dışında bağımlılığı yoktur) ve bu yüzden sıralama
/// regresyonları simülatörsüz test edilir.
public struct BM25Index: Sendable {
    /// Terim sıklığı doygunluk parametresi. 1.2 standart değerdir: bir terimin 10 kez geçmesi
    /// 2 kez geçmesinden daha alakalı sayılır ama 5 kat değil.
    private let k1: Double
    /// Belge uzunluğu normalizasyonu. 0.75 standart: uzun belgeler cezalandırılır ama
    /// tamamen elenmez.
    private let b: Double

    /// term → (documentID → terim sıklığı)
    private var postings: [String: [String: Int]] = [:]
    /// documentID → toplam token sayısı
    private var documentLengths: [String: Int] = [:]
    /// documentID → belgede geçen terimler. Silmeyi sözlük büyüklüğünden bağımsız kılar:
    /// bu ters harita olmadan tek bir belgeyi çıkarmak tüm sözlüğü taramayı gerektirirdi.
    private var documentTerms: [String: Set<String>] = [:]

    public init(k1: Double = 1.2, b: Double = 0.75) {
        self.k1 = k1
        self.b = b
    }

    public var documentCount: Int { documentLengths.count }

    private var averageDocumentLength: Double {
        guard !documentLengths.isEmpty else { return 0 }
        return Double(documentLengths.values.reduce(0, +)) / Double(documentLengths.count)
    }

    // MARK: - İndeksleme

    /// Belgeyi indeksler; aynı kimlikle çağrılırsa eskisinin yerini alır.
    ///
    /// - Parameters:
    ///   - title: başlık tokenları `titleBoost` kez tekrarlanarak eklenir. Başlıkta geçen
    ///     terim gövdede geçenden daha güçlü sinyaldir; bunu skor formülünde ayrı bir alan
    ///     olarak modellemek yerine tekrarla ifade etmek indeksi basit tutar.
    public mutating func index(
        documentID: String,
        title: String,
        body: String,
        tags: [String],
        titleBoost: Int = 2
    ) {
        remove(documentID: documentID)

        var tokens = TextNormalizer.tokenize(body)
        let titleTokens = TextNormalizer.tokenize(title)
        for _ in 0 ..< max(1, titleBoost) {
            tokens.append(contentsOf: titleTokens)
        }
        tokens.append(contentsOf: tags.flatMap { TextNormalizer.tokenize($0) })

        guard !tokens.isEmpty else { return }

        var frequencies: [String: Int] = [:]
        for token in tokens {
            frequencies[token, default: 0] += 1
        }
        for (term, frequency) in frequencies {
            postings[term, default: [:]][documentID] = frequency
        }
        documentLengths[documentID] = tokens.count
        documentTerms[documentID] = Set(frequencies.keys)
    }

    public mutating func remove(documentID: String) {
        documentLengths.removeValue(forKey: documentID)
        guard let terms = documentTerms.removeValue(forKey: documentID) else { return }
        for term in terms {
            postings[term]?.removeValue(forKey: documentID)
            if postings[term]?.isEmpty == true {
                postings.removeValue(forKey: term)
            }
        }
    }

    public mutating func removeAll() {
        postings.removeAll()
        documentLengths.removeAll()
        documentTerms.removeAll()
    }

    // MARK: - Arama

    /// Sorgu tokenları için belge kimliği → ham BM25 skoru.
    ///
    /// Yalnız **en az bir terimi içeren** belgeler döner; hiçbir terimi geçmeyen belge
    /// sonuç kümesine hiç girmez (0 skorla değil).
    public func scores(for query: String) -> [String: Double] {
        let terms = Set(TextNormalizer.tokenize(query))
        guard !terms.isEmpty, documentCount > 0 else { return [:] }

        let totalDocuments = Double(documentCount)
        let averageLength = averageDocumentLength
        var results: [String: Double] = [:]

        for term in terms {
            guard let posting = postings[term], !posting.isEmpty else { continue }
            let documentFrequency = Double(posting.count)
            // Sık geçen terimler (her belgede olan "toplam") neredeyse hiç ayırt etmez;
            // idf bunu otomatik olarak sıfıra yaklaştırır.
            let idf = log(1 + (totalDocuments - documentFrequency + 0.5) / (documentFrequency + 0.5))

            for (documentID, frequency) in posting {
                let length = Double(documentLengths[documentID] ?? 0)
                let normalization = k1 * (1 - b + b * (averageLength > 0 ? length / averageLength : 1))
                let termFrequency = Double(frequency)
                results[documentID, default: 0] +=
                    idf * (termFrequency * (k1 + 1)) / (termFrequency + normalization)
            }
        }
        return results
    }

    /// Skorları `0...1` aralığına indirger.
    ///
    /// BM25 skorları korpusa göre ölçeklenir; hibrit skorda embedding benzerliğiyle (0...1)
    /// toplanabilmesi için normalize edilmeleri gerekir (04 §6).
    public static func normalized(_ scores: [String: Double]) -> [String: Double] {
        guard let maximum = scores.values.max(), maximum > 0 else { return scores }
        return scores.mapValues { $0 / maximum }
    }
}
