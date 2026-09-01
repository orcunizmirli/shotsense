import AppFoundation
import Foundation
import ShotCore

/// Arama ekranının durumu.
///
/// Arama iki aşamalıdır (02 §2.3): kullanıcı yazarken **anında** yerel anahtar kelime
/// sonuçları gösterilir, duraklayınca doğal dil ayrıştırması çalışır. Böylece arayüz
/// hiçbir zaman modeli beklemez.
@MainActor
@Observable
public final class SearchViewModel {
    public enum ViewState: Equatable {
        case idle
        case searching
        case results([SearchResult])
        case noResults
        case quotaExceeded
    }

    public var queryText = "" {
        didSet { scheduleInstantSearch() }
    }

    public private(set) var state: ViewState = .idle
    /// Ayrıştırılan filtreler; kullanıcıya çip olarak gösterilir ve kaldırılabilir.
    public private(set) var appliedIntent: SearchIntent?
    public private(set) var isParsing = false

    private let dependencies: LibraryDependencies
    private let paywall: PaywallPresenter
    private let dateProvider: any DateProviding
    private var instantSearchTask: Task<Void, Never>?

    /// Doğal dil ayrıştırması için beklenen duraklama. 400 ms, kullanıcının yazmayı
    /// bitirdiğini anlamaya yeter ama gecikme olarak hissedilmez.
    private let parseDebounce: Duration = .milliseconds(400)

    public init(
        dependencies: LibraryDependencies,
        paywall: PaywallPresenter,
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.dependencies = dependencies
        self.paywall = paywall
        self.dateProvider = dateProvider
    }

    // MARK: - Anlık arama

    private func scheduleInstantSearch() {
        instantSearchTask?.cancel()
        let text = queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            appliedIntent = nil
            state = .idle
            return
        }

        instantSearchTask = Task { [weak self] in
            // Görev sıraya girdikten sonra kullanıcı Enter'a basmış olabilir; o durumda
            // submit() bu görevi iptal eder ve buradan hiç devam edilmemelidir.
            guard let self, !Task.isCancelled else { return }
            // Ham metinle hemen ara: model beklenmeden ilk sonuçlar görünür.
            await run(intent: .plain(text))
            try? await Task.sleep(for: parseDebounce)
            guard !Task.isCancelled else { return }
            await parseAndSearch(text)
        }
    }

    // MARK: - Doğal dil araması

    /// Kullanıcı Enter'a bastığında veya duraklama dolduğunda çalışır.
    public func submit() async {
        instantSearchTask?.cancel()
        let text = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await parseAndSearch(text)
    }

    private func parseAndSearch(_ text: String) async {
        isParsing = true
        defer { isParsing = false }

        let intent = await dependencies.analyzer.parseSearchIntent(text)

        // Kota yalnız modelin gerçekten bir filtre çıkardığı sorgularda tüketilir: heuristik
        // olarak çözülen "geçen ay fişler" kullanıcının hakkını yemez (06 §3).
        if intent.hasFilters {
            guard await dependencies.quota.consume(.naturalLanguageSearch) else {
                paywall.presentAutomatically(.searchQuotaExhausted)
                state = .quotaExceeded
                return
            }
        }
        await run(intent: intent)
    }

    private func run(intent: SearchIntent) async {
        if case .idle = state { state = .searching }
        appliedIntent = intent

        let query = SearchQuery.resolving(intent, now: dateProvider.now)
        do {
            let results = try await dependencies.index.search(query)
            state = results.isEmpty ? .noResults : .results(results)
        } catch {
            Log.error(.search, "Arama başarısız", error: error)
            state = .noResults
        }
    }

    // MARK: - Filtre çipleri

    /// Kullanıcı bir çipi kaldırdığında filtreyi düşürüp yeniden arar.
    public func removeCategoryFilter() async {
        guard let intent = appliedIntent else { return }
        await run(
            intent: SearchIntent(
                freeText: intent.freeText,
                category: nil,
                dateRange: intent.dateRange,
                minAmount: intent.minAmount,
                maxAmount: intent.maxAmount
            )
        )
    }

    public func removeDateFilter() async {
        guard let intent = appliedIntent else { return }
        await run(
            intent: SearchIntent(
                freeText: intent.freeText,
                category: intent.category,
                dateRange: nil,
                minAmount: intent.minAmount,
                maxAmount: intent.maxAmount
            )
        )
    }

    public func removeAmountFilter() async {
        guard let intent = appliedIntent else { return }
        await run(
            intent: SearchIntent(
                freeText: intent.freeText,
                category: intent.category,
                dateRange: intent.dateRange,
                minAmount: nil,
                maxAmount: nil
            )
        )
    }

    public func clear() {
        instantSearchTask?.cancel()
        queryText = ""
        appliedIntent = nil
        state = .idle
    }
}
