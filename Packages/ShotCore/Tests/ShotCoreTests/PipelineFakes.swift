import Foundation
@testable import ShotCore

// Pipeline testleri için sahte portlar. Domain yalnız protokollere bağlı olduğu için
// tüm akış (öncelik, sınır, hata, yetim temizliği) Vision/Photos/SwiftData olmadan koşar.

actor FakeShotSource: ShotSourcing {
    var assets: [ShotAsset]
    var authorization: ShotLibraryAuthorization
    /// Bu kimlikler için görsel yükleme hata verir.
    var failingIdentifiers: Set<String> = []
    var thrownError: AppError = .init(.notFound, "test")
    private(set) var imageRequests: [(identifier: String, maxPixelSize: Int)] = []
    private(set) var deletedIdentifiers: [String] = []

    init(assets: [ShotAsset] = [], authorization: ShotLibraryAuthorization = .authorized) {
        self.assets = assets
        self.authorization = authorization
    }

    func setAssets(_ assets: [ShotAsset]) { self.assets = assets }
    func setAuthorization(_ value: ShotLibraryAuthorization) { authorization = value }
    func setFailing(_ identifiers: Set<String>, error: AppError) {
        failingIdentifiers = identifiers
        thrownError = error
    }

    var authorizationStatus: ShotLibraryAuthorization { authorization }
    func requestAuthorization() async -> ShotLibraryAuthorization { authorization }

    func screenshots(newerThan date: Date?) async throws -> [ShotAsset] {
        assets
            .filter { date.map { cutoff in $0.createdAt > cutoff } ?? true }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func imageData(for identifier: String, maxPixelSize: Int) async throws -> Data {
        imageRequests.append((identifier, maxPixelSize))
        if failingIdentifiers.contains(identifier) { throw thrownError }
        return Data("görsel:\(identifier)".utf8)
    }

    nonisolated func changes() -> AsyncStream<ShotLibraryChange> {
        AsyncStream { $0.finish() }
    }

    func deleteAssets(identifiers: [String]) async throws {
        deletedIdentifiers.append(contentsOf: identifiers)
        assets.removeAll { identifiers.contains($0.identifier) }
    }
}

struct FakeTextRecognizer: TextRecognizing {
    /// Görsel verisinden üretilecek metin; nil ise kimliğe göre sabit metin üretilir.
    var text: String?

    func recognize(imageData: Data, languages: [String]) async throws -> RecognizedDocument {
        let content = text ?? String(decoding: imageData, as: UTF8.self)
        return RecognizedDocument(
            blocks: [.init(text: content, verticalPosition: 0.1, relativeHeight: 0.03)],
            languages: ["tr-TR"]
        )
    }
}

struct FakeAnalyzer: ShotAnalyzing {
    let kind: AnalyzerKind = .heuristic
    var category: ShotCategory = .receipt
    var shouldThrow = false

    var isAvailable: Bool { get async { true } }

    func analyze(_ document: RecognizedDocument) async throws -> ShotAnalysis {
        if shouldThrow { throw AppError(.unknown, "analiz patladı") }
        return ShotAnalysis(
            category: category,
            categoryConfidence: 0.9,
            title: "başlık",
            summary: "özet",
            tags: ["etiket"],
            entities: [],
            analyzerKind: .heuristic
        )
    }

    func parseSearchIntent(_ query: String) async -> SearchIntent { .plain(query) }
}

actor FakeIndex: ShotIndexing {
    private(set) var storage: [String: Shot] = [:]
    private(set) var thumbnails: [String: Data] = [:]
    private(set) var upsertCount = 0

    func upsert(_ shot: Shot) async throws { try await upsert([shot]) }

    func upsert(_ shots: [Shot]) async throws {
        upsertCount += 1
        for shot in shots { storage[shot.assetIdentifier] = shot }
    }

    func remove(assetIdentifiers: [String]) async throws {
        for identifier in assetIdentifiers { storage.removeValue(forKey: identifier) }
    }

    func shot(assetIdentifier: String) async throws -> Shot? { storage[assetIdentifier] }

    func search(_ query: SearchQuery) async throws -> [SearchResult] {
        storage.values
            .filter { query.matchesFilters($0) }
            .map { SearchResult(shot: $0, score: 1) }
    }

    func shots(category: ShotCategory?, limit: Int, offset: Int) async throws -> [Shot] {
        let sorted = storage.values
            .filter { category.map { wanted in $0.analysis.category == wanted } ?? true }
            .sorted { $0.createdAt > $1.createdAt }
        guard offset < sorted.count else { return [] }
        return Array(sorted[offset ..< min(offset + limit, sorted.count)])
    }

    func pendingAssetIdentifiers(limit: Int) async throws -> [String] {
        storage.values
            .filter { if case .pending = $0.status { return true } else { return false } }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map(\.assetIdentifier)
    }

    func counts() async throws -> IndexCounts {
        var analyzed = 0
        var pending = 0
        var failed = 0
        for shot in storage.values {
            switch shot.status {
            case .analyzed: analyzed += 1
            case .failed: failed += 1
            case .orphaned: break
            default: pending += 1
            }
        }
        return IndexCounts(
            total: analyzed + pending + failed, analyzed: analyzed, pending: pending, failed: failed
        )
    }

    func setThumbnail(_ data: Data, for assetIdentifier: String) async throws {
        thumbnails[assetIdentifier] = data
    }

    func thumbnail(for assetIdentifier: String) async throws -> Data? {
        thumbnails[assetIdentifier]
    }

    func resetIndex() async throws {
        storage.removeAll()
        thumbnails.removeAll()
    }
}
