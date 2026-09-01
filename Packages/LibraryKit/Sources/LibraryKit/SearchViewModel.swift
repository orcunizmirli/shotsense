import AppFoundation
import CoreGraphics
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
    /// Boşta ekranda gösterilen son aramalar (en yeniden eskiye, en fazla 6).
    ///
    /// Bellekte tutulur, diske yazılmaz: arama sorguları kullanıcının ne aradığını
    /// ele verir ve `UserDefaults` yedeklemeye girer (07 §4).
    public private(set) var recentQueries: [String] = []

    /// Sonuç satırlarındaki önizlemeler. Kitaplıkla aynı toplayıcı/önbellek mantığı:
    /// sonuç listesi de hızlı kaydırılır ve aynı takılma riskini taşır.
    public let thumbnails: ThumbnailStore

    private let dependencies: LibraryDependencies
    private let paywall: PaywallPresenter
    private let dateProvider: any DateProviding
    private var instantSearchTask: Task<Void, Never>?

    /// Anlık (anahtar kelime) arama için beklenen duraklama.
    ///
    /// Her tuş vuruşunda indekse gitmek, hızlı yazan kullanıcıda saniyede 8-10 arama
    /// demektir; her biri sonuç listesini baştan kurar ve yazarken gözle görülür takılma
    /// yaratır. 140 ms iki tuş arasına sığmayacak kadar kısa, gecikme hissettirmeyecek
    /// kadar da uzundur.
    private let instantDebounce: Duration = .milliseconds(140)
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
        thumbnails = ThumbnailStore(index: dependencies.index)
    }

    public func image(for result: SearchResult) -> CGImage? {
        thumbnails.image(for: result.shot.assetIdentifier)
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

            try? await Task.sleep(for: instantDebounce)
            guard !Task.isCancelled else { return }
            // Ham metinle ara: model beklenmeden ilk sonuçlar görünür.
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
        remember(text)

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
            // İlk ekran dolusu önizleme hemen istenir; kullanıcı listeyi görür görmez
            // görseller yerine oturur.
            thumbnails.prefetch(results.prefix(12).map(\.shot.assetIdentifier))
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

    /// Sorguyu son aramalara ekler (tekrarları öne taşır).
    private func remember(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        recentQueries.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentQueries.insert(trimmed, at: 0)
        if recentQueries.count > 6 { recentQueries.removeLast(recentQueries.count - 6) }
    }

    /// Öneri veya son aramaya dokunulduğunda.
    public func apply(suggestion: String) async {
        queryText = suggestion
        await submit()
    }

    public func clear() {
        instantSearchTask?.cancel()
        queryText = ""
        appliedIntent = nil
        state = .idle
    }
}
