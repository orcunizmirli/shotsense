import EventKit

/// İzin durumundan ne yapılacağına karar veren saf mantık.
///
/// Ayrı bir tip olmasının sebebi test edilebilirlik: gerçek izin diyaloğu olmadan
/// "hangi durumda izin isteriz, hangisinde doğrudan reddederiz" kuralı doğrulanabilmeli.
/// Yanlış karar iki yönde de kötüdür — gereksiz diyalog sürtünme, eksik istek ise
/// sessizce çalışmayan bir düğme yaratır.
public enum EventKitAccessPolicy {
    public enum Decision: Equatable {
        /// Yetki var, doğrudan devam.
        case proceed
        /// Henüz sorulmamış; sistem diyaloğu gösterilir.
        case request
        /// Kullanıcı reddetmiş veya kısıtlı; Ayarlar'a yönlendirilir.
        case denied
    }

    /// Hatırlatıcılar **tam erişim** gerektirir: EventKit hatırlatıcılar için yazma-yalnız
    /// erişim sunmaz.
    public static func remindersDecision(for status: EKAuthorizationStatus) -> Decision {
        switch status {
        case .fullAccess: return .proceed
        case .notDetermined: return .request
        default: return .denied
        }
    }

    /// Takvim için **yazma-yalnız** yeterlidir: uygulama kullanıcının etkinliklerini okumaz,
    /// yalnız yeni etkinlik ekler. Daha az izin istemek hem doğru hem App Review'da
    /// açıklaması kolaydır (07 §5).
    public static func calendarDecision(for status: EKAuthorizationStatus) -> Decision {
        switch status {
        case .fullAccess, .writeOnly: return .proceed
        case .notDetermined: return .request
        default: return .denied
        }
    }
}
