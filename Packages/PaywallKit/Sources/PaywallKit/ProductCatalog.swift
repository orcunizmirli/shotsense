import Foundation

/// Ürün kimlikleri (06 §2). App Store Connect'teki kimliklerle **birebir** eşleşmelidir.
public enum ProductCatalog {
    public static let yearly = "com.shotsense.pro.yearly"
    public static let monthly = "com.shotsense.pro.monthly"

    /// Sunum sırası: yıllık önce gelir ve varsayılan seçilir (06 §2).
    public static let allIdentifiers = [yearly, monthly]

    /// Pro yetkisi veren kimlikler. Gelecekte `lifetime` eklenecek (v1.1).
    public static let proIdentifiers: Set<String> = [yearly, monthly]
}
