import AppFoundation
import ShotCore
import Testing
@testable import LibraryKit

@MainActor
@Suite("PaywallPresenter")
struct PaywallPresenterTests {
    @Test("Otomatik paywall ayda en fazla 3 kez gösterilir")
    func monthlyCapIsEnforced() {
        // KANON §11: sınırsız paywall, kullanıcıyı uygulamadan soğutur.
        let clock = MutableDateProvider()
        let presenter = PaywallPresenter(dateProvider: clock)

        var shownCount = 0
        for _ in 0 ..< 6 {
            if presenter.presentAutomatically(.indexLimitReached) { shownCount += 1 }
            presenter.isPresented = false
            clock.advance(by: 72 * 3600)
        }

        #expect(shownCount == 3)
    }

    @Test("İki gösterim arasında en az 48 saat olur")
    func cooldownIsEnforced() {
        let clock = MutableDateProvider()
        let presenter = PaywallPresenter(dateProvider: clock)

        #expect(presenter.presentAutomatically(.indexLimitReached))
        presenter.isPresented = false

        clock.advance(by: 24 * 3600)
        #expect(!presenter.presentAutomatically(.searchQuotaExhausted))

        clock.advance(by: 25 * 3600)
        #expect(presenter.presentAutomatically(.searchQuotaExhausted))
    }

    @Test("30 günlük pencere kayarak yenilenir")
    func windowSlides() {
        let clock = MutableDateProvider()
        let presenter = PaywallPresenter(dateProvider: clock)

        for _ in 0 ..< 3 {
            presenter.presentAutomatically(.indexLimitReached)
            presenter.isPresented = false
            clock.advance(by: 72 * 3600)
        }
        #expect(!presenter.presentAutomatically(.indexLimitReached))

        clock.advance(by: 31 * 86400)
        #expect(presenter.presentAutomatically(.indexLimitReached))
    }

    @Test("Kullanıcının kendi açtığı paywall kapağa takılmaz")
    func manualPresentationIgnoresCap() {
        let clock = MutableDateProvider()
        let presenter = PaywallPresenter(dateProvider: clock)

        for _ in 0 ..< 3 {
            presenter.presentAutomatically(.indexLimitReached)
            presenter.isPresented = false
            clock.advance(by: 72 * 3600)
        }

        presenter.presentManually()
        #expect(presenter.isPresented)
        #expect(presenter.trigger == .settings)
    }

    @Test("Her tetikleyicinin başlığı tanımlı", arguments: PaywallTrigger.allCases)
    func everyTriggerHasHeadline(_ trigger: PaywallTrigger) {
        #expect(!PaywallView.headline(for: trigger).isEmpty)
    }
}
