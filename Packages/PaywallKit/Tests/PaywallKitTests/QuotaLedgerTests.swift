import AppFoundation
import Foundation
import ShotCore
import ShotCoreTestSupport
import Testing
@testable import PaywallKit

@Suite("QuotaLedger")
struct QuotaLedgerTests {
    /// Her test kendi UserDefaults alanını kullanır; testler birbirinin sayacını görmemeli.
    private func makeSuiteName() -> String {
        "quota-test-" + UUID().uuidString
    }

    /// Aynı alana bağlı **yeni** bir `UserDefaults` örneği verir.
    ///
    /// Tek bir örneği iki aktöre geçirmek Swift 6'da veri yarışı riski sayılır
    /// (`UserDefaults` `Sendable` değildir). Aynı `suiteName` ile ayrı örnekler almak
    /// altta yatan aynı depoyu paylaşır — testin kastettiği de budur.
    private func makeDefaults(suite: String) throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suite))
    }

    @Test("Free kullanıcı aylık sınıra kadar tüketir")
    func freeUserConsumesUpToLimit() async throws {
        let ledger = QuotaLedger(
            defaults: try makeDefaults(suite: makeSuiteName()),
            dateProvider: MutableDateProvider(),
            entitlements: FakeEntitlementProvider(entitlement: .free)
        )

        for _ in 0 ..< MeteredCapability.action.monthlyLimit {
            #expect(await ledger.consume(.action))
        }
        #expect(await ledger.consume(.action) == false)
        #expect(await ledger.remaining(.action) == 0)
    }

    @Test("Pro kullanıcıda sınır yok")
    func proUserIsUnlimited() async throws {
        let ledger = QuotaLedger(
            defaults: try makeDefaults(suite: makeSuiteName()),
            dateProvider: MutableDateProvider(),
            entitlements: FakeEntitlementProvider(entitlement: Entitlement(tier: .pro))
        )

        for _ in 0 ..< 50 {
            #expect(await ledger.consume(.action))
        }
        #expect(await ledger.remaining(.action) == .max)
    }

    @Test("Pro kullanıcıda sayaç artmaz")
    func proUsageDoesNotAccumulate() async throws {
        // Abonelik biterse eski aylardan devreden bir "borç" oluşmamalı.
        let suite = makeSuiteName()
        let clock = MutableDateProvider()
        let proLedger = QuotaLedger(
            defaults: try makeDefaults(suite: suite),
            dateProvider: clock,
            entitlements: FakeEntitlementProvider(entitlement: Entitlement(tier: .pro))
        )
        for _ in 0 ..< 10 { _ = await proLedger.consume(.action) }

        let freeLedger = QuotaLedger(
            defaults: try makeDefaults(suite: suite),
            dateProvider: clock,
            entitlements: FakeEntitlementProvider(entitlement: .free)
        )
        #expect(await freeLedger.remaining(.action) == MeteredCapability.action.monthlyLimit)
    }

    @Test("Ay değişince kota kendiliğinden yenilenir")
    func quotaResetsNextMonth() async throws {
        let clock = MutableDateProvider(now: Date(timeIntervalSince1970: 1_767_225_600))
        let ledger = QuotaLedger(
            defaults: try makeDefaults(suite: makeSuiteName()),
            dateProvider: clock,
            entitlements: FakeEntitlementProvider(entitlement: .free)
        )
        while await ledger.consume(.action) {}
        #expect(await ledger.remaining(.action) == 0)

        clock.advance(by: 32 * 86400)

        #expect(await ledger.remaining(.action) == MeteredCapability.action.monthlyLimit)
    }

    @Test("Yetenekler birbirinin kotasını tüketmez")
    func capabilitiesAreIndependent() async throws {
        let ledger = QuotaLedger(
            defaults: try makeDefaults(suite: makeSuiteName()),
            dateProvider: MutableDateProvider(),
            entitlements: FakeEntitlementProvider(entitlement: .free)
        )
        while await ledger.consume(.action) {}

        #expect(await ledger.remaining(.naturalLanguageSearch)
            == MeteredCapability.naturalLanguageSearch.monthlyLimit)
    }

    @Test("Dönem kimliği UTC takvim ayıdır")
    func periodIdentifierIsUTCMonth() {
        // Kullanıcının yereli/saat dilimi değişince kota "sıfırlanmamalı".
        let date = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
        #expect(QuotaLedger.periodIdentifier(for: date) == "2026-01")
    }

    @Test("Katalogdaki her ürün Pro yetkisi verir")
    func catalogProductsGrantPro() {
        for identifier in ProductCatalog.allIdentifiers {
            #expect(ProductCatalog.proIdentifiers.contains(identifier))
        }
    }
}
