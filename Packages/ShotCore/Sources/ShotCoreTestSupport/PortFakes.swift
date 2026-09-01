import AppFoundation
import Foundation
import ShotCore

// Testler için sahte port gerçeklemeleri.
//
// Domain ve arayüz yalnız protokollere bağlı olduğu için tüm akışlar (pipeline, kitaplık,
// arama, kota, paywall) Vision/Photos/SwiftData/StoreKit olmadan koşabilir. Bu tipler
// ürün derlemesine girmez; yalnız test hedefleri bağlar.

public actor FakeShotSource: ShotSourcing {
    public private(set) var assets: [ShotAsset]
    private var authorization: ShotLibraryAuthorization
    private var failingIdentifiers: Set<String> = []
    private var thrownError = AppError(.notFound, "test")
    public private(set) var imageRequests: [(identifier: String, maxPixelSize: Int)] = []
    public private(set) var deletedIdentifiers: [String] = []

    public init(assets: [ShotAsset] = [], authorization: ShotLibraryAuthorization = .authorized) {
        self.assets = assets
        self.authorization = authorization
    }

    public func setAssets(_ assets: [ShotAsset]) { self.assets = assets }
    public func setAuthorization(_ value: ShotLibraryAuthorization) { authorization = value }
    public func setFailing(_ identifiers: Set<String>, error: AppError) {
        failingIdentifiers = identifiers
        thrownError = error
    }

    public var authorizationStatus: ShotLibraryAuthorization { authorization }
    public func requestAuthorization() async -> ShotLibraryAuthorization { authorization }

    public func screenshots(newerThan date: Date?) async throws -> [ShotAsset] {
        assets
            .filter { asset in date.map { asset.createdAt > $0 } ?? true }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func imageData(for identifier: String, maxPixelSize: Int) async throws -> Data {
        imageRequests.append((identifier, maxPixelSize))
        if failingIdentifiers.contains(identifier) { throw thrownError }
        return Data("görsel:\(identifier)".utf8)
    }

    public nonisolated func changes() -> AsyncStream<ShotLibraryChange> {
        AsyncStream { $0.finish() }
    }

    public func deleteAssets(identifiers: [String]) async throws {
        deletedIdentifiers.append(contentsOf: identifiers)
        assets.removeAll { identifiers.contains($0.identifier) }
    }
}

public struct FakeTextRecognizer: TextRecognizing {
    public var text: String?

    public init(text: String? = nil) { self.text = text }

    public func recognize(imageData: Data, languages: [String]) async throws -> RecognizedDocument {
        let content = text ?? (String(data: imageData, encoding: .utf8) ?? "")
        return RecognizedDocument(
            blocks: [.init(text: content, verticalPosition: 0.1, relativeHeight: 0.03)],
            languages: ["tr-TR"]
        )
    }
}

public struct FakeAnalyzer: ShotAnalyzing {
    public let kind: AnalyzerKind = .heuristic
    public var category: ShotCategory
    public var shouldThrow: Bool
    /// `parseSearchIntent` bunu döner; nil ise sorgu düz metin kalır.
    public var intent: SearchIntent?

    public init(
        category: ShotCategory = .receipt,
        shouldThrow: Bool = false,
        intent: SearchIntent? = nil
    ) {
        self.category = category
        self.shouldThrow = shouldThrow
        self.intent = intent
    }

    public var isAvailable: Bool { get async { true } }

    public func analyze(_ document: RecognizedDocument) async throws -> ShotAnalysis {
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

    public func parseSearchIntent(_ query: String) async -> SearchIntent {
        intent ?? .plain(query)
    }
}

public actor FakeIndex: ShotIndexing {
    public private(set) var storage: [String: Shot] = [:]
    public private(set) var thumbnails: [String: Data] = [:]
    public private(set) var searchQueries: [SearchQuery] = []
    /// Testler toplu okuma yapıldığını doğrular: hücre başına tek tek okuma performans
    /// gerilemesidir ve sessizce geri gelebilir.
    public private(set) var thumbnailBatchRequests: [[String]] = []
    public private(set) var categoryCountRequests = 0
    private var shouldFail = false

    public init(shots: [Shot] = []) {
        for shot in shots { storage[shot.assetIdentifier] = shot }
    }

    public func setShouldFail(_ value: Bool) { shouldFail = value }

    public func upsert(_ shot: Shot) async throws { try await upsert([shot]) }

    public func upsert(_ shots: [Shot]) async throws {
        if shouldFail { throw AppError(.unknown, "yazma başarısız") }
        for shot in shots { storage[shot.assetIdentifier] = shot }
    }

    public func remove(assetIdentifiers: [String]) async throws {
        for identifier in assetIdentifiers { storage.removeValue(forKey: identifier) }
    }

    public func shot(assetIdentifier: String) async throws -> Shot? { storage[assetIdentifier] }

    public func search(_ query: SearchQuery) async throws -> [SearchResult] {
        searchQueries.append(query)
        if shouldFail { throw AppError(.unknown, "arama başarısız") }
        return storage.values
            .filter { query.matchesFilters($0) }
            .filter { shot in
                let text = query.intent.freeText
                return text.isEmpty || TextNormalizer.fold(shot.recognizedText + shot.analysis.title)
                    .contains(TextNormalizer.fold(text))
            }
            .sorted { $0.createdAt > $1.createdAt }
            .map { SearchResult(shot: $0, score: 1, snippet: $0.analysis.summary) }
    }

    public func shots(category: ShotCategory?, limit: Int, offset: Int) async throws -> [Shot] {
        if shouldFail { throw AppError(.unknown, "okuma başarısız") }
        let sorted = storage.values
            .filter { shot in category.map { shot.analysis.category == $0 } ?? true }
            .sorted { $0.createdAt > $1.createdAt }
        guard offset < sorted.count else { return [] }
        return Array(sorted[offset ..< min(offset + limit, sorted.count)])
    }

    public func pendingAssetIdentifiers(limit: Int) async throws -> [String] {
        storage.values
            .filter { $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map(\.assetIdentifier)
    }

    public func counts() async throws -> IndexCounts {
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

    public func setThumbnail(_ data: Data, for assetIdentifier: String) async throws {
        thumbnails[assetIdentifier] = data
    }

    public func thumbnail(for assetIdentifier: String) async throws -> Data? {
        thumbnails[assetIdentifier]
    }

    public func thumbnails(for assetIdentifiers: [String]) async throws -> [String: Data] {
        thumbnailBatchRequests.append(assetIdentifiers)
        return thumbnails.filter { assetIdentifiers.contains($0.key) }
    }

    public func categoryCounts() async throws -> [ShotCategory: Int] {
        categoryCountRequests += 1
        return storage.values.reduce(into: [:]) { counts, shot in
            counts[shot.analysis.category, default: 0] += 1
        }
    }

    public func resetIndex() async throws {
        storage.removeAll()
        thumbnails.removeAll()
    }
}

public actor FakeActionPerformer: ActionPerforming {
    public private(set) var reminders: [ReminderDraft] = []
    public private(set) var events: [CalendarEventDraft] = []
    private var errorToThrow: AppError?

    public init() {}

    public func setError(_ error: AppError?) { errorToThrow = error }

    public func createReminder(_ draft: ReminderDraft) async throws {
        if let errorToThrow { throw errorToThrow }
        reminders.append(draft)
    }

    public func createCalendarEvent(_ draft: CalendarEventDraft) async throws {
        if let errorToThrow { throw errorToThrow }
        events.append(draft)
    }
}

public actor FakeEntitlementProvider: EntitlementProviding {
    private var entitlement: Entitlement
    private var products: [PurchasableProduct]
    public private(set) var purchasedIdentifiers: [String] = []
    public private(set) var restoreCount = 0

    public init(entitlement: Entitlement = .free, products: [PurchasableProduct] = []) {
        self.entitlement = entitlement
        self.products = products
    }

    public var current: Entitlement { entitlement }

    public nonisolated func updates() -> AsyncStream<Entitlement> {
        AsyncStream { $0.finish() }
    }

    public func availableProducts() async throws -> [PurchasableProduct] { products }

    public func purchase(productIdentifier: String) async throws -> PurchaseOutcome {
        purchasedIdentifiers.append(productIdentifier)
        entitlement = Entitlement(tier: .pro)
        return .purchased
    }

    public func restorePurchases() async throws { restoreCount += 1 }
}

public actor FakeQuotaMeter: QuotaMetering {
    private var remainingByCapability: [MeteredCapability: Int]

    public init(remaining: [MeteredCapability: Int] = [:]) {
        remainingByCapability = remaining
    }

    public func remaining(_ capability: MeteredCapability) async -> Int {
        remainingByCapability[capability] ?? capability.monthlyLimit
    }

    public func consume(_ capability: MeteredCapability) async -> Bool {
        let left = remainingByCapability[capability] ?? capability.monthlyLimit
        guard left > 0 else { return false }
        remainingByCapability[capability] = left - 1
        return true
    }
}

public final class FakeClipboard: ClipboardWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(text: String, isSensitive: Bool)] = []

    public init() {}

    public func copy(_ text: String, isSensitive: Bool) {
        lock.lock()
        defer { lock.unlock() }
        entries.append((text, isSensitive))
    }

    public var copied: [(text: String, isSensitive: Bool)] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

public actor FakeSettingsStore: SettingsStoring {
    private var current: FeatureFlags

    public init(flags: FeatureFlags = .default) { current = flags }

    public func flags() async -> FeatureFlags { current }
    public func update(_ flags: FeatureFlags) async { current = flags }
}
