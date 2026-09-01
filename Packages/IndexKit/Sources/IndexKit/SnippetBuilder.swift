import Foundation
import ShotCore

/// Arama sonucunda gösterilecek metin parçasını üretir.
///
/// Sonuç listesinde ilk 100 karakteri göstermek işe yaramaz: eşleşme genelde ekranın
/// ortasındadır ve kullanıcı *neden* bu sonucun döndüğünü göremez. Bu tip eşleşen terimin
/// çevresini keser, böylece sonuç kendini açıklar.
public enum SnippetBuilder {
    public static func snippet(
        for query: String,
        in text: String,
        contextLength: Int = 60
    ) -> String {
        let normalizedText = text.replacingOccurrences(of: "\n", with: " ")
        let terms = TextNormalizer.tokenize(query)
        guard !terms.isEmpty, !normalizedText.isEmpty else {
            return String(normalizedText.prefix(contextLength * 2))
        }

        let folded = TextNormalizer.fold(normalizedText)
        // Katlama Türkçe/İngilizce için 1:1'dir, ama her betik için garanti değildir. Uzunluk
        // tutmuyorsa offset'ler kayar ve yanlış yerden keseriz; o durumda baştan kesmek doğru.
        guard folded.count == normalizedText.count else {
            return String(normalizedText.prefix(contextLength * 2))
        }
        // En uzun terim en ayırt edicidir; ondan başlayarak eşleşme aranır.
        for term in terms.sorted(by: { $0.count > $1.count }) {
            guard let range = folded.range(of: term) else { continue }
            return excerpt(around: range, in: normalizedText, folded: folded, contextLength: contextLength)
        }
        return String(normalizedText.prefix(contextLength * 2))
    }

    private static func excerpt(
        around range: Range<String.Index>,
        in text: String,
        folded: String,
        contextLength: Int
    ) -> String {
        // Çağıran taraf uzunluk eşitliğini doğruladı; offset'ler iki dizede aynı yeri gösterir.
        let matchStart = folded.distance(from: folded.startIndex, to: range.lowerBound)
        let matchLength = folded.distance(from: range.lowerBound, to: range.upperBound)

        let start = max(0, matchStart - contextLength)
        let end = min(text.count, matchStart + matchLength + contextLength)
        guard start < end else { return String(text.prefix(contextLength * 2)) }

        let lower = text.index(text.startIndex, offsetBy: start)
        let upper = text.index(text.startIndex, offsetBy: end)
        var excerpt = String(text[lower ..< upper]).trimmingCharacters(in: .whitespaces)

        if start > 0 { excerpt = "…" + excerpt }
        if end < text.count { excerpt += "…" }
        return excerpt
    }
}
