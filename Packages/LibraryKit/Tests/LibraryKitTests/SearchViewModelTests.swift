import AppFoundation
import ShotCore
import ShotCoreTestSupport
import Testing
@testable import LibraryKit

@MainActor
@Suite("SearchViewModel")
struct SearchViewModelTests {
    private func makeModel(
        index: FakeIndex,
        analyzer: FakeAnalyzer = FakeAnalyzer(),
        quota: FakeQuotaMeter = FakeQuotaMeter(),
        paywall: PaywallPresenter = PaywallPresenter()
    ) -> SearchViewModel {
        SearchViewModel(
            dependencies: TestDependencies.make(index: index, analyzer: analyzer, quota: quota),
            paywall: paywall,
            dateProvider: MutableDateProvider(now: TestDependencies.epoch)
        )
    }

    @Test("Boş sorgu boşta durumuna döner")
    func emptyQueryIsIdle() {
        let model = makeModel(index: FakeIndex())
        model.queryText = "fiş"
        model.queryText = ""
        #expect(model.state == .idle)
    }

    @Test("Sonuç bulunursa listelenir")
    func resultsAreListed() async {
        let index = FakeIndex(shots: [TestDependencies.shot(text: "kulaklık siparişi")])
        let model = makeModel(index: index)

        model.queryText = "kulaklık"
        await model.submit()

        guard case let .results(results) = model.state else {
            Issue.record("sonuç bekleniyordu, \(model.state) geldi")
            return
        }
        #expect(results.count == 1)
    }

    @Test("Eşleşme yoksa sonuç yok durumu")
    func noResultsState() async {
        let model = makeModel(index: FakeIndex(shots: [TestDependencies.shot()]))

        model.queryText = "bulunmayanterim"
        await model.submit()

        #expect(model.state == .noResults)
    }

    @Test("Filtre çıkarılmayan sorgu kota tüketmez")
    func plainQueryDoesNotConsumeQuota() async {
        // Heuristik olarak çözülen sorgu kullanıcının aylık hakkını yememeli (06 §3).
        let quota = FakeQuotaMeter(remaining: [.naturalLanguageSearch: 1])
        let model = makeModel(index: FakeIndex(), quota: quota)

        model.queryText = "kulaklık"
        await model.submit()

        #expect(await quota.remaining(.naturalLanguageSearch) == 1)
    }

    @Test("Filtre çıkaran sorgu kota tüketir")
    func filteredQueryConsumesQuota() async {
        let quota = FakeQuotaMeter(remaining: [.naturalLanguageSearch: 2])
        let analyzer = FakeAnalyzer(intent: SearchIntent(freeText: "", category: .receipt))
        let model = makeModel(index: FakeIndex(), analyzer: analyzer, quota: quota)

        model.queryText = "fişler"
        await model.submit()

        #expect(await quota.remaining(.naturalLanguageSearch) == 1)
    }

    @Test("Kota bitince paywall açılır ve durum kota aşımı olur")
    func exhaustedQuotaPresentsPaywall() async {
        let quota = FakeQuotaMeter(remaining: [.naturalLanguageSearch: 0])
        let analyzer = FakeAnalyzer(intent: SearchIntent(freeText: "", category: .receipt))
        let paywall = PaywallPresenter()
        let model = makeModel(index: FakeIndex(), analyzer: analyzer, quota: quota, paywall: paywall)

        model.queryText = "fişler"
        await model.submit()

        #expect(model.state == .quotaExceeded)
        #expect(paywall.trigger == .searchQuotaExhausted)
    }

    @Test("Ayrıştırılan filtreler kullanıcıya gösterilir")
    func appliedFiltersAreExposed() async {
        let analyzer = FakeAnalyzer(
            intent: SearchIntent(freeText: "kulaklık", category: .receipt, dateRange: .last30Days)
        )
        let model = makeModel(index: FakeIndex(), analyzer: analyzer)

        model.queryText = "geçen ay kulaklık fişi"
        await model.submit()

        #expect(model.appliedIntent?.category == .receipt)
        #expect(model.appliedIntent?.dateRange == .last30Days)
    }

    @Test("Çip kaldırılınca filtre düşer ve yeniden aranır")
    func removingChipDropsFilter() async {
        let analyzer = FakeAnalyzer(
            intent: SearchIntent(freeText: "kulaklık", category: .receipt, dateRange: .last30Days)
        )
        let model = makeModel(index: FakeIndex(), analyzer: analyzer)
        model.queryText = "geçen ay kulaklık fişi"
        await model.submit()

        await model.removeCategoryFilter()

        #expect(model.appliedIntent?.category == nil)
        #expect(model.appliedIntent?.dateRange == .last30Days)
    }

    @Test("Temizleme her şeyi sıfırlar")
    func clearResetsState() async {
        let model = makeModel(index: FakeIndex(shots: [TestDependencies.shot()]))
        model.queryText = "fiş"
        await model.submit()

        model.clear()

        #expect(model.state == .idle)
        #expect(model.appliedIntent == nil)
        #expect(model.queryText.isEmpty)
    }
}
