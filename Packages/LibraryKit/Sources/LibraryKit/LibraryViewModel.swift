import AppFoundation
import CoreGraphics
import Foundation
import ShotCore

/// Kitaplık ızgarasının durumu.
@MainActor
@Observable
public final class LibraryViewModel {
    public enum ViewState: Equatable {
        case loading
        case permissionRequired
        case empty
        case content([Shot])
        case failed(String)

        var shots: [Shot] {
            if case let .content(shots) = self { return shots }
            return []
        }
    }

    public private(set) var state: ViewState = .loading
    public private(set) var progress: IndexingProgress?
    public private(set) var selectedCategory: ShotCategory?
    /// Kategori çipleri: yalnız kitaplıkta gerçekten bulunan kategoriler, sayılarıyla.
    public private(set) var categoryCounts: [(category: ShotCategory, count: Int)] = []

    public let thumbnails: ThumbnailStore

    private let dependencies: LibraryDependencies
    private let dateProvider: any DateProviding

    private let pageSize = 60
    /// Bir hücre göründüğünde kaç hücre ilerisinin önizlemesi istenir.
    ///
    /// 3 sütunlu ızgarada 15 hücre ≈ 5 satır ≈ bir ekran boyu ileri. Daha azı kaydırırken
    /// boş kare gösterir, daha fazlası gereksiz iş ve bellek demektir.
    private let prefetchWindow = 15

    private var isLoadingMore = false
    private var hasMorePages = true
    /// İlerleme akışı dinleyicisi. İndeksleme bitince iptal edilir; aksi hâlde ekran her
    /// açıldığında yeni bir dinleyici doğar ve hiçbiri ölmez.
    private var progressTask: Task<Void, Never>?
    /// İndeksleme sürerken ızgaranın ne sıklıkta yenileneceği.
    ///
    /// Her partide (25 kayıt) yenilemek ızgarayı saniyede birkaç kez baştan kurar ve
    /// kaydırmayı gözle görülür biçimde takar. Yenileme kısılır; ilerleme rozeti zaten
    /// canlı güncellenir, dolayısıyla kullanıcı sistemin çalıştığını görmeye devam eder.
    private let refreshThrottle: TimeInterval = 2.0
    private var lastRefreshAt: Date = .distantPast

    public init(
        dependencies: LibraryDependencies,
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.dependencies = dependencies
        self.dateProvider = dateProvider
        thumbnails = ThumbnailStore(index: dependencies.index)
    }

    // MARK: - Yükleme

    public func load() async {
        let authorization = await dependencies.source.authorizationStatus
        guard authorization == .authorized || authorization == .limited else {
            state = .permissionRequired
            return
        }
        await reload()
    }

    public func requestPermission() async {
        let result = await dependencies.source.requestAuthorization()
        guard result == .authorized || result == .limited else {
            state = .permissionRequired
            return
        }
        state = .loading
        await reload()
    }

    public func reload() async {
        hasMorePages = true
        lastRefreshAt = dateProvider.now
        do {
            async let shotsTask = dependencies.index.shots(
                category: selectedCategory, limit: pageSize, offset: 0
            )
            async let countsTask = dependencies.index.categoryCounts()

            let shots = try await shotsTask
            let counts = try await countsTask

            categoryCounts = ShotCategory.allCases
                .compactMap { category in
                    guard let count = counts[category], count > 0 else { return nil }
                    return (category, count)
                }
                .sorted { $0.count > $1.count }

            state = shots.isEmpty ? .empty : .content(shots)
            hasMorePages = shots.count == pageSize
            thumbnails.prefetch(shots.prefix(prefetchWindow * 2).map(\.assetIdentifier))
        } catch {
            Log.error(.ui, "Kitaplık yüklenemedi", error: error)
            state = .failed("Kitaplık yüklenemedi.")
        }
    }

    /// Sonsuz kaydırma + önizleme ön yüklemesi.
    public func cellAppeared(_ shot: Shot) async {
        let shots = state.shots
        guard let position = shots.firstIndex(of: shot) else { return }

        // Görünen hücreden ileriye doğru pencere: kullanıcı oraya varmadan görseller hazır.
        let upperBound = min(position + prefetchWindow, shots.count)
        thumbnails.prefetch(shots[position ..< upperBound].map(\.assetIdentifier))

        await loadMoreIfNeeded(at: position, total: shots.count)
    }

    private func loadMoreIfNeeded(at position: Int, total: Int) async {
        guard hasMorePages, !isLoadingMore, position >= total - 12 else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let next = try await dependencies.index.shots(
                category: selectedCategory, limit: pageSize, offset: total
            )
            guard !next.isEmpty else {
                hasMorePages = false
                return
            }
            state = .content(state.shots + next)
            hasMorePages = next.count == pageSize
        } catch {
            hasMorePages = false
        }
    }

    /// Kategori değişimi.
    ///
    /// Durum `.loading`'e **düşürülmez**: mevcut içerik yerinde kalır ve yenisi gelince
    /// yumuşakça değişir. Araya iskelet ekranı sokmak, hızlı çip değiştiren kullanıcıda
    /// ekranın yanıp sönmesine yol açar.
    public func select(category: ShotCategory?) async {
        guard selectedCategory != category else { return }
        selectedCategory = category
        await reload()
    }

    // MARK: - İndeksleme

    /// Kitaplık senkronizasyonunu başlatır ve ilerlemeyi dinler.
    public func startIndexing() async {
        do {
            try await dependencies.pipeline.synchronizeLibrary()
            await refreshIfStale(force: true)
        } catch {
            Log.warning(.ui, "Senkronizasyon başarısız")
        }

        let pipeline = dependencies.pipeline
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            for await update in await pipeline.progress() {
                guard !Task.isCancelled else { return }
                self?.progress = update
            }
        }
        defer {
            progressTask?.cancel()
            progressTask = nil
            progress = nil
        }

        while await pipeline.processPending(limit: 25) > 0 {
            if Task.isCancelled { return }
            await refreshIfStale(force: false)
        }
        await refreshIfStale(force: true)
    }

    /// Kısıtlı yenileme: son yenilemeden bu yana yeterli süre geçtiyse ızgarayı tazeler.
    private func refreshIfStale(force: Bool) async {
        guard force || dateProvider.now.timeIntervalSince(lastRefreshAt) >= refreshThrottle
        else { return }
        await reload()
    }

    // MARK: - Önizleme

    public func image(for shot: Shot) -> CGImage? {
        thumbnails.image(for: shot.assetIdentifier)
    }
}
