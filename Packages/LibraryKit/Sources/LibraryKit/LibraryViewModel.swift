import AppFoundation
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
    }

    public private(set) var state: ViewState = .loading
    public private(set) var progress: IndexingProgress?
    public var selectedCategory: ShotCategory?
    /// Kategori çipleri; yalnız kitaplıkta gerçekten bulunan kategoriler gösterilir.
    public private(set) var availableCategories: [ShotCategory] = []

    private let dependencies: LibraryDependencies
    private var thumbnails: [String: Data] = [:]
    private var pageSize = 60
    private var isLoadingMore = false
    private var hasMorePages = true

    public init(dependencies: LibraryDependencies) {
        self.dependencies = dependencies
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
        await reload()
    }

    public func reload() async {
        hasMorePages = true
        do {
            let shots = try await dependencies.index.shots(
                category: selectedCategory, limit: pageSize, offset: 0
            )
            availableCategories = try await loadAvailableCategories()
            state = shots.isEmpty ? .empty : .content(shots)
            hasMorePages = shots.count == pageSize
        } catch {
            Log.error(.ui, "Kitaplık yüklenemedi", error: error)
            state = .failed("Kitaplık yüklenemedi.")
        }
    }

    /// Sonsuz kaydırma: son hücreye yaklaşınca çağrılır.
    public func loadMoreIfNeeded(currentItem shot: Shot) async {
        guard case let .content(shots) = state, hasMorePages, !isLoadingMore else { return }
        // Son 10 hücreden birine gelindiğinde yükle: tam sona bırakmak boş ekran gösterir.
        guard let index = shots.firstIndex(of: shot), index >= shots.count - 10 else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let next = try await dependencies.index.shots(
                category: selectedCategory, limit: pageSize, offset: shots.count
            )
            guard !next.isEmpty else {
                hasMorePages = false
                return
            }
            state = .content(shots + next)
            hasMorePages = next.count == pageSize
        } catch {
            hasMorePages = false
        }
    }

    public func select(category: ShotCategory?) async {
        guard selectedCategory != category else { return }
        selectedCategory = category
        state = .loading
        await reload()
    }

    private func loadAvailableCategories() async throws -> [ShotCategory] {
        var found: [ShotCategory] = []
        for category in ShotCategory.allCases {
            let sample = try await dependencies.index.shots(category: category, limit: 1, offset: 0)
            if !sample.isEmpty { found.append(category) }
        }
        return found
    }

    // MARK: - İndeksleme

    /// Kitaplık senkronizasyonunu başlatır ve ilerlemeyi dinler.
    public func startIndexing() async {
        do {
            try await dependencies.pipeline.synchronizeLibrary()
        } catch {
            Log.warning(.ui, "Senkronizasyon başarısız")
        }

        // İlerleme akışı ekrandan bağımsız yaşar; görev iptal edilince dinleme de biter.
        let pipeline = dependencies.pipeline
        Task { @MainActor [weak self] in
            for await update in await pipeline.progress() {
                self?.progress = update
            }
        }

        while await dependencies.pipeline.processPending(limit: 25) > 0 {
            await reload()
            if Task.isCancelled { return }
        }
        await reload()
    }

    // MARK: - Önizleme

    public func thumbnail(for shot: Shot) -> Data? {
        thumbnails[shot.assetIdentifier]
    }

    public func loadThumbnail(for shot: Shot) async {
        guard thumbnails[shot.assetIdentifier] == nil else { return }
        guard let data = try? await dependencies.index.thumbnail(for: shot.assetIdentifier)
        else { return }
        thumbnails[shot.assetIdentifier] = data
    }
}
