import SwiftUI

/// Tasarım belirteçleri. KANON §2: asset katalogu yok — tüm ölçüler, renkler ve hareketler
/// kodda tanımlıdır.
///
/// **Neden belirteç:** premium his tutarlılıktan doğar. Ekranlar kendi aralık ve punto
/// değerlerini uydurduğunda arayüz "ucuz" görünür; göz bunu bilinçli olarak fark etmez ama
/// ritim bozukluğunu hisseder.
public enum Token {
    /// 4 pt'lik ızgara. Ara değer kullanılmaz.
    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
    }

    /// Köşe yarıçapları. Yuvalanmış yüzeylerde dıştan içe küçülür ki köşeler eşmerkezli
    /// görünsün (iç yarıçap = dış yarıçap − dolgu).
    public enum Radius {
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 10
        public static let md: CGFloat = 14
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 28
        public static let pill: CGFloat = 999
    }

    /// Erişilebilirlik: dokunma hedefleri bu değerin altına inmez (02 §4).
    public static let minimumTapTarget: CGFloat = 44

    /// Kitaplık ızgarası sütun sayısı, Dynamic Type boyutuna göre.
    ///
    /// Büyük punto seçen kullanıcıda 3 sütun okunamaz hâle gelir; ızgara daralır.
    public static func gridColumns(for sizeCategory: DynamicTypeSize) -> Int {
        switch sizeCategory {
        case .xSmall, .small, .medium, .large: return 3
        case .xLarge, .xxLarge, .xxxLarge: return 2
        default: return 1
        }
    }

    // MARK: - Hareket

    /// Hareket belirteçleri.
    ///
    /// Hepsi **yay** tabanlıdır, süre tabanlı değil: yaylar kesintiye uğradığında hızını
    /// koruyarak yeni hedefe yönelir. Kullanıcı bir animasyon biterken ikinci kez
    /// dokunduğunda süre tabanlı eğri "zıplar", yay akmaya devam eder. Akıcılığın
    /// büyük kısmı bu farktan gelir.
    public enum Motion {
        /// Görünüm/kaybolma, liste ekleme-çıkarma. Sönümlü, taşma yok.
        public static let standard = Animation.smooth(duration: 0.32)
        /// Dokunma geri bildirimi, seçim değişimi. Kısa ve keskin.
        public static let quick = Animation.snappy(duration: 0.22, extraBounce: 0.02)
        /// Vurgulu anlar (başarı, ödül). Hafif taşma.
        public static let expressive = Animation.bouncy(duration: 0.45, extraBounce: 0.15)
        /// Sürekli/tekrarlı efektler (iskelet parıltısı).
        public static let ambient = Animation.easeInOut(duration: 1.1)

        /// "Hareketi Azalt" açıkken animasyonu kaldırır.
        ///
        /// Vestibüler rahatsızlığı olan kullanıcılar için bu bir konfor değil erişilebilirlik
        /// gereğidir; ölçek/kayma animasyonları baş dönmesi yapabilir.
        public static func respectingReduceMotion(
            _ animation: Animation,
            isReduced: Bool
        ) -> Animation? {
            isReduced ? nil : animation
        }
    }

    // MARK: - Tipografi

    /// Tipografi ölçeği.
    ///
    /// Sistem fontu üzerine kurulur (Dynamic Type otomatik çalışır), ama ağırlık ve harf
    /// aralığı elle ayarlanır: iri puntoda sıkı, küçük puntoda ferah aralık okunabilirliği
    /// belirgin biçimde artırır ve metne "tasarlanmış" bir his verir.
    public enum Typography {
        public static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
        public static let title = Font.system(.title2, design: .rounded, weight: .semibold)
        public static let headline = Font.system(.headline, design: .default, weight: .semibold)
        public static let body = Font.system(.body)
        public static let callout = Font.system(.callout)
        public static let caption = Font.system(.caption, weight: .medium)
        public static let micro = Font.system(.caption2, weight: .semibold)
        /// Sayısal değerler (tutar, tarih): tabular rakam hizalaması sayıların zıplamasını önler.
        public static let numeric = Font.system(.body, design: .rounded, weight: .medium)
            .monospacedDigit()
    }
}

// MARK: - Yüzeyler

public extension ShapeStyle where Self == Color {
    /// Kart ve rozet zeminleri.
    ///
    /// Sistem semantik renklerinden türetilir; karanlık modda ayrı tanım gerekmez ve
    /// kullanıcının kontrast ayarlarına uyar.
    static var surface: Color { Color.primary.opacity(0.06) }
    static var surfaceStrong: Color { Color.primary.opacity(0.11) }
    /// Kart kenarındaki saç teli çizgi. Gölge yerine çizgi: gölge kaydırmada yeniden
    /// çizim maliyeti yaratır ve karanlık modda kirli görünür.
    static var hairline: Color { Color.primary.opacity(0.09) }
}

public extension View {
    /// Standart kart yüzeyi: yumuşak zemin + saç teli kenar.
    func surfaceCard(radius: CGFloat = Token.Radius.lg) -> some View {
        background(.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.hairline, lineWidth: 0.5)
            }
    }

    /// Yüzen kapsül (bildirim balonu, ilerleme rozeti).
    ///
    /// Gölge `compositingGroup` sonrası uygulanır: aksi hâlde SwiftUI gölgeyi alt
    /// katmanların her biri için ayrı hesaplar ve kaydırmada kare düşer.
    func floatingCapsule() -> some View {
        background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous).strokeBorder(.hairline, lineWidth: 0.5)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    /// Yüzen panel (alt aksiyon çubuğu).
    func floatingPanel(radius: CGFloat = Token.Radius.xl) -> some View {
        background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.hairline, lineWidth: 0.5)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.14), radius: 18, y: 6)
    }
}
