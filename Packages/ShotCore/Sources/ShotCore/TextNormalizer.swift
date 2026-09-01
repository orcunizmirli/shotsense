import Foundation

/// Metin karşılaştırmalarının tek noktası: grounding doğrulaması, arama tokenizasyonu ve
/// yinelenen tespiti aynı normalizasyonu kullanmalıdır, aksi hâlde "bulundu/bulunamadı"
/// kararları katmanlar arasında tutarsızlaşır.
public enum TextNormalizer {
    /// Aksan ve büyük/küçük harf duyarsız karşılaştırma biçimi.
    ///
    /// **Türkçe I sorunu:** `MİGROS` ile `migros` eşleşmelidir, ama hiçbir yerel bunu tek
    /// başına vermez. Türkçe yerelinde katlama `İ`'yi önce `I`'ya indirger, sonra Türkçe
    /// kuralıyla `ı` yapar → `mıgros`; kök yerelinde ise `ı` ile `i` ayrışır. Bu yüzden
    /// noktalı/noktasız I varyantları **katlamadan önce** tek biçime indirgenir ve katlama
    /// yerelden bağımsız yapılır.
    ///
    /// Bu bir dil kuralı değil, **arama eşleştirme** kuralıdır: amaç doğru Türkçe küçük harf
    /// üretmek değil, kullanıcının yazdığıyla ekrandakini buluşturmaktır.
    public static func fold(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "İ", with: "I")
            .replacingOccurrences(of: "ı", with: "i")
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                locale: nil
            )
    }

    /// Yalnızca harf ve rakamları bırakır — biçimlendirme farklarını (boşluk, nokta, tire)
    /// yok sayarak sayısal/kimlik değerlerini karşılaştırmak için.
    ///
    /// Örn. `TR33 0006 1005 1978 6457 8413 26` ile `TR330006100519786457841326` eşleşir.
    public static func alphanumeric(_ value: String) -> String {
        fold(value).filter { $0.isLetter || $0.isNumber }
    }

    /// Yalnızca rakamları bırakır — tutar ve telefon karşılaştırması için.
    public static func digits(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    /// Arama ve BM25 için token listesi. Harf/rakam dizileri; 2 karakterden kısa olanlar atılır.
    public static func tokenize(_ value: String) -> [String] {
        fold(value)
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            .filter { $0.count >= 2 }
    }
}
