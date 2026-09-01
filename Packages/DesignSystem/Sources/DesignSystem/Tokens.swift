import SwiftUI

/// Tasarım belirteçleri. KANON §2: asset katalogu yok — tüm renkler ve ölçüler kodda tanımlı.
public enum Token {
    /// 4 pt'lik bir ızgaraya oturur; ara değer kullanılmaz ki ekranlar arası ritim bozulmasın.
    public enum Space {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Radius {
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 20
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
}

public extension ShapeStyle where Self == Color {
    /// Kart ve rozet zeminleri. Sistem semantik renkleri kullanılır ki karanlık modda
    /// ayrı tanım gerekmesin.
    static var surface: Color { Color.gray.opacity(0.12) }
    static var surfaceStrong: Color { Color.gray.opacity(0.2) }
}
