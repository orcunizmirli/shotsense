import AppFoundation
import Foundation
import ShotCore

/// `ShotIndexing` portunun gerçeklemesi: SwiftData kalıcılığı + BM25 + cümle vektörleri.
///
/// **Neden bellek-içi indeks:** 5.000 belge için sözlük ~4 MB, vektörler ~10 MB tutar; bu
/// modern bir iPhone'da sorun değil. Diske özel bir ikili biçim yazmak (ve onu göç ettirmek)
/// ancak kitaplık on binlere çıkınca kazanç sağlar. Kaynak veri SwiftData'da durduğu için
/// indeks her açılışta kayıpsız yeniden kurulabilir — bu, biçim göçü diye bir sorunu
/// tamamen ortadan kaldırır (05 §5).
public actor HybridIndex: ShotIndexing {
    /// Hibrit skor ağırlıkları (04 §6). Toplamları 1'dir.
    enum Weight {
        static let term = 0.6
        static let semantic = 0.3
        static let recency = 0.1
        /// Anlamsal bileşen kullanılamıyorsa (vektör modeli yok) ağırlığı terime devredilir.
        static let termWithoutSemantic = term + semantic
    }

    /// Tazelik yarılanma ölçeği (gün). 180 gün önceki bir sonuç bugünkünün ~%37'si kadar
    /// tazelik puanı alır — eski ama alakalı sonuçları ezmeyecek kadar yumuşak.
    static let recencyDecayDays = 180.0

    private let store: ShotStore
    private let embeddings: EmbeddingProvider

    private var bm25 = BM25Index()
    private var documents: [String: IndexedDocument] = [:]
    private var isWarm = false

    public init(store: ShotStore, embeddings: EmbeddingProvider = EmbeddingProvider()) {
        self.store = store
        self.embeddings = embeddings
    }

    /// Kalıcı depodan bellek-içi indeksi kurar. Uygulama açılışında bir kez çağrılır.
    public func warmUp() async throws {
        guard !isWarm else { return }
        let payloads = try await store.indexingPayloads()
        for payload in payloads {
            bm25.index(
                documentID: payload.identifier,
                title: payload.title,
                body: payload.body,
                tags: payload.tags
            )
        }
        for document in try await store.allDocuments() {
            documents[document.assetIdentifier] = document
        }
        isWarm = true
        Log.info(.index, "Arama indeksi kuruldu", detail: "\(documents.count) belge")
    }

    // MARK: - Yazma

    public func upsert(_ shot: Shot) async throws {
        try await upsert([shot])
    }

    public func upsert(_ shots: [Shot]) async throws {
        try await store.upsert(shots)
        for shot in shots {
            bm25.index(
                documentID: shot.assetIdentifier,
                title: shot.analysis.title,
                body: shot.recognizedText + "\n" + shot.analysis.summary,
                tags: shot.analysis.tags
            )
            documents[shot.assetIdentifier] = IndexedDocument(
                assetIdentifier: shot.assetIdentifier,
                createdAt: shot.createdAt,
                category: shot.analysis.category,
                amounts: shot.filterAmounts,
                title: shot.analysis.title,
                summary: shot.analysis.summary,
                tags: shot.analysis.tags,
                embedding: embeddings.vector(for: Self.embeddingText(for: shot))
            )
        }
    }

    /// Vektör **tam OCR metninden değil**, başlık + özet + etiketlerden üretilir.
    ///
    /// Ekran görüntüsü metni arayüz gürültüsüyle doludur ("Geri", "Paylaş", saat, pil);
    /// cümle vektörü bu gürültüde anlamı kaybeder. Damıtılmış metin çok daha ayırt edici
    /// bir vektör verir — anahtar kelime tarafı zaten ham metni BM25 ile kapsıyor.
    static func embeddingText(for shot: Shot) -> String {
        [shot.analysis.title, shot.analysis.summary, shot.analysis.tags.joined(separator: " ")]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    public func remove(assetIdentifiers: [String]) async throws {
        try await store.remove(assetIdentifiers: assetIdentifiers)
        for identifier in assetIdentifiers {
            bm25.remove(documentID: identifier)
            documents.removeValue(forKey: identifier)
        }
    }

    public func setThumbnail(_ data: Data, for assetIdentifier: String) async throws {
        try await store.setThumbnail(data, for: assetIdentifier)
    }

    public func thumbnail(for assetIdentifier: String) async throws -> Data? {
        try await store.thumbnail(for: assetIdentifier)
    }

    public func resetIndex() async throws {
        try await store.reset()
        bm25.removeAll()
        documents.removeAll()
    }

    // MARK: - Okuma

    public func shot(assetIdentifier: String) async throws -> Shot? {
        try await store.shot(assetIdentifier: assetIdentifier)
    }

    public func shots(category: ShotCategory?, limit: Int, offset: Int) async throws -> [Shot] {
        try await store.shots(category: category, limit: limit, offset: offset)
    }

    public func pendingAssetIdentifiers(limit: Int) async throws -> [String] {
        let pending = try await store.pendingIdentifiers(limit: limit)
        guard pending.count < limit else { return pending }
        // Bekleyen kalmadıysa şeması eskimiş kayıtlar düşük öncelikle yeniden analiz edilir.
        let stale = try await store.staleIdentifiers(limit: limit - pending.count)
        return pending + stale
    }

    public func counts() async throws -> IndexCounts {
        try await store.counts()
    }

    // MARK: - Arama

    public func search(_ query: SearchQuery) async throws -> [SearchResult] {
        try await warmUp()

        let candidates = documents.values.filter { query.matchesFilters($0) }
        guard !candidates.isEmpty else { return [] }

        let freeText = query.intent.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let ranked = freeText.isEmpty
            ? rankByRecency(candidates, limit: query.limit)
            : rank(candidates, freeText: freeText, limit: query.limit)

        guard !ranked.isEmpty else { return [] }

        let shots = try await store.shots(assetIdentifiers: ranked.map(\.identifier))
        let shotsByIdentifier = Dictionary(
            shots.map { ($0.assetIdentifier, $0) }, uniquingKeysWith: { first, _ in first }
        )

        return ranked.compactMap { scored in
            guard let shot = shotsByIdentifier[scored.identifier] else { return nil }
            return SearchResult(
                shot: shot,
                score: scored.total,
                termScore: scored.term,
                semanticScore: scored.semantic,
                recencyScore: scored.recency,
                snippet: freeText.isEmpty
                    ? shot.analysis.summary
                    : SnippetBuilder.snippet(for: freeText, in: shot.recognizedText)
            )
        }
    }

    // MARK: - Sıralama

    struct ScoredDocument {
        let identifier: String
        let total: Double
        let term: Double
        let semantic: Double
        let recency: Double
    }

    private func rank(
        _ candidates: [IndexedDocument],
        freeText: String,
        limit: Int
    ) -> [ScoredDocument] {
        let termScores = BM25Index.normalized(bm25.scores(for: freeText))
        let queryVector = embeddings.vector(for: freeText)
        let now = Date()

        let semanticAvailable = queryVector != nil
        let termWeight = semanticAvailable ? Weight.term : Weight.termWithoutSemantic
        let semanticWeight = semanticAvailable ? Weight.semantic : 0

        var scored: [ScoredDocument] = []
        for document in candidates {
            let term = termScores[document.assetIdentifier] ?? 0
            let semantic: Double = {
                guard let queryVector, let vector = document.embedding else { return 0 }
                // Kosinüs -1...1 aralığındadır; negatif benzerlik "alakasız" demektir,
                // 0'a kırpılır ki skoru aşağı çekmesin.
                return max(0, EmbeddingProvider.similarity(queryVector, vector))
            }()
            let recency = Self.recencyScore(for: document.createdAt, now: now)

            // Ne terim ne anlamsal eşleşme varsa belge sonuç değildir; tazelik tek başına
            // bir şeyi sonuç yapmaz (aksi hâlde her sorgu tüm kitaplığı döndürürdü).
            guard term > 0 || semantic > 0.5 else { continue }

            scored.append(
                ScoredDocument(
                    identifier: document.assetIdentifier,
                    total: termWeight * term + semanticWeight * semantic + Weight.recency * recency,
                    term: term,
                    semantic: semantic,
                    recency: recency
                )
            )
        }

        return Array(
            scored
                .sorted { lhs, rhs in
                    // Eşit skorda daha yeni olan öne geçer; sıralama deterministik olmalı.
                    lhs.total == rhs.total ? lhs.identifier < rhs.identifier : lhs.total > rhs.total
                }
                .prefix(limit)
        )
    }

    /// Serbest metin yoksa (yalnız filtreli sorgu) sonuçlar tarihe göre sıralanır.
    private func rankByRecency(_ candidates: [IndexedDocument], limit: Int) -> [ScoredDocument] {
        let now = Date()
        return candidates
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { document in
                let recency = Self.recencyScore(for: document.createdAt, now: now)
                return ScoredDocument(
                    identifier: document.assetIdentifier,
                    total: recency,
                    term: 0,
                    semantic: 0,
                    recency: recency
                )
            }
    }

    static func recencyScore(for date: Date, now: Date) -> Double {
        let ageDays = max(0, now.timeIntervalSince(date) / 86400)
        return exp(-ageDays / recencyDecayDays)
    }
}
