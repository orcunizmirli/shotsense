import AppFoundation
import Foundation
import ShotCore

/// Free katman kotalarının cihaz-içi sayacı (06 §4).
///
/// **Sunucu yok, dolayısıyla kurcalanabilir.** Bu bilinçli bir kabuldür: kotayı sunucuda
/// doğrulamak bir arka uç, hesap sistemi ve kullanıcı verisi toplamayı gerektirirdi —
/// yani ürünün tek satış argümanını (hiçbir şey cihazdan çıkmaz) yok ederdi. Kaybedilen
/// gelir, kazanılan gizlilik iddiasının yanında önemsizdir.
///
/// Sayaçlar **döneme göre anahtarlanır** (`quota.action.2026-03`): ayrı bir "sıfırlama"
/// adımı yoktur, ay değişince yeni anahtar kendiliğinden sıfırdan başlar. Bu, cihaz saati
/// geri alındığında bile geçmiş dönemin sayacını korur.
public actor QuotaLedger: QuotaMetering {
    private let defaults: UserDefaults
    private let dateProvider: any DateProviding
    private let entitlements: any EntitlementProviding

    private static let keyPrefix = "quota."

    /// - Parameter suiteName: testlerin birbirinin sayacını görmemesi için ayrı alan;
    ///   `nil` üretim davranışıdır (`UserDefaults.standard`).
    ///
    /// Depo **aktörün içinde** kurulur, dışarıdan alınmaz: `UserDefaults` `Sendable`
    /// değildir ve bir örneği aktör sınırından geçirmek Swift 6'da veri yarışı riski
    /// sayılır. Alan adı (`String?`) geçirmek hem güvenli hem yeterlidir.
    public init(
        suiteName: String? = nil,
        dateProvider: any DateProviding = SystemDateProvider(),
        entitlements: any EntitlementProviding
    ) {
        defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.dateProvider = dateProvider
        self.entitlements = entitlements
    }

    public func remaining(_ capability: MeteredCapability) async -> Int {
        let entitlement = await entitlements.current
        guard !entitlement.isPro else { return .max }
        return max(0, capability.monthlyLimit - used(capability))
    }

    public func consume(_ capability: MeteredCapability) async -> Bool {
        let entitlement = await entitlements.current
        // Pro kullanıcıda sayaç hiç artırılmaz: abonelik biterse eski aylardan devreden
        // bir "borç" oluşmamalı.
        guard !entitlement.isPro else { return true }

        let current = used(capability)
        guard current < capability.monthlyLimit else { return false }
        defaults.set(current + 1, forKey: key(for: capability))
        return true
    }

    private func used(_ capability: MeteredCapability) -> Int {
        defaults.integer(forKey: key(for: capability))
    }

    private func key(for capability: MeteredCapability) -> String {
        Self.keyPrefix + capability.rawValue + "." + Self.periodIdentifier(for: dateProvider.now)
    }

    /// `yyyy-MM` — takvim ayı. Kullanıcının yereline göre değişmemesi için sabit takvim
    /// ve UTC kullanılır; aksi hâlde uçak yolculuğunda kota "sıfırlanabilirdi".
    static func periodIdentifier(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }
}
