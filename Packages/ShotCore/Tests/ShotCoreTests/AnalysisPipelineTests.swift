import Foundation
import Testing
@testable import ShotCore

@Suite("AnalysisPipeline")
struct AnalysisPipelineTests {
    private let epoch = Date(timeIntervalSince1970: 1_767_225_600)

    private func assets(_ count: Int, from base: Date) -> [ShotAsset] {
        (0 ..< count).map { index in
            ShotAsset(
                identifier: "asset-\(index)",
                // index 0 en yeni.
                createdAt: base.addingTimeInterval(-Double(index) * 3600),
                pixelWidth: 1290,
                pixelHeight: 2796
            )
        }
    }

    private func makePipeline(
        source: FakeShotSource,
        index: FakeIndex,
        analyzer: FakeAnalyzer = FakeAnalyzer(),
        indexLimit: Int? = nil
    ) -> AnalysisPipeline {
        AnalysisPipeline(
            source: source,
            recognizer: FakeTextRecognizer(),
            analyzer: analyzer,
            index: index,
            dateProvider: MutableDateProvider(now: epoch),
            concurrency: 2,
            indexLimit: indexLimit
        )
    }

    // MARK: - Keşif

    @Test("Yeni ekran görüntüleri bekleyen olarak kuyruğa alınır")
    func synchronizeQueuesNewAssets() async throws {
        let source = FakeShotSource(assets: assets(5, from: epoch))
        let index = FakeIndex()
        let pipeline = makePipeline(source: source, index: index)

        let added = try await pipeline.synchronizeLibrary()

        #expect(added == 5)
        #expect(await index.storage.count == 5)
        #expect(await index.storage.values.allSatisfy { $0.status == .pending })
    }

    @Test("İkinci senkronizasyon aynı kayıtları tekrar eklemez")
    func synchronizeIsIdempotent() async throws {
        let source = FakeShotSource(assets: assets(3, from: epoch))
        let index = FakeIndex()
        let pipeline = makePipeline(source: source, index: index)

        try await pipeline.synchronizeLibrary()
        let secondRun = try await pipeline.synchronizeLibrary()

        #expect(secondRun == 0)
        #expect(await index.storage.count == 3)
    }

    @Test("Free katman sınırı yalnız en yeni N görseli indeksler")
    func freeTierLimitKeepsNewest() async throws {
        // Sınır davranışı ürünün para modelinin çekirdeği (06 §3): en yeniler indekslenmeli,
        // eskiler değil — aksi hâlde kullanıcı yükseltme baskısını hiç hissetmez.
        let source = FakeShotSource(assets: assets(10, from: epoch))
        let index = FakeIndex()
        let pipeline = makePipeline(source: source, index: index, indexLimit: 4)

        try await pipeline.synchronizeLibrary()

        let identifiers = Set(await index.storage.keys)
        #expect(identifiers == ["asset-0", "asset-1", "asset-2", "asset-3"])
    }

    @Test("Photos'tan silinmiş kayıt yetim olarak temizlenir")
    func removedAssetsAreCleanedUp() async throws {
        let source = FakeShotSource(assets: assets(3, from: epoch))
        let index = FakeIndex()
        let pipeline = makePipeline(source: source, index: index)
        try await pipeline.synchronizeLibrary()

        await source.setAssets(assets(3, from: epoch).filter { $0.identifier != "asset-1" })
        try await pipeline.synchronizeLibrary()

        #expect(await index.storage["asset-1"] == nil)
        #expect(await index.storage.count == 2)
    }

    @Test("İzin yoksa senkronizasyon hata verir")
    func synchronizeRequiresAuthorization() async {
        let source = FakeShotSource(assets: [], authorization: .denied)
        let pipeline = makePipeline(source: source, index: FakeIndex())

        await #expect(throws: AppError.self) {
            try await pipeline.synchronizeLibrary()
        }
    }

    @Test("Sınırlı erişimde de çalışır")
    func limitedAuthorizationIsAccepted() async throws {
        // Kullanıcı tam erişim vermediyse ürün kapanmaz; seçtiği görsellerle çalışır (07 §2).
        let source = FakeShotSource(assets: assets(2, from: epoch), authorization: .limited)
        let pipeline = makePipeline(source: source, index: FakeIndex())
        #expect(try await pipeline.synchronizeLibrary() == 2)
    }

    // MARK: - İşleme

    @Test("Bekleyen kayıtlar analiz edilir ve indekslenir")
    func processPendingAnalyzesQueue() async throws {
        let source = FakeShotSource(assets: assets(3, from: epoch))
        let index = FakeIndex()
        let pipeline = makePipeline(source: source, index: index)
        try await pipeline.synchronizeLibrary()

        let processed = await pipeline.processPending()

        #expect(processed == 3)
        let shots = Array(await index.storage.values)
        #expect(shots.allSatisfy { $0.status == .analyzed })
        #expect(shots.allSatisfy { $0.analysis.title == "başlık" })
        #expect(shots.allSatisfy { $0.indexedAt != nil })
    }

    @Test("Analiz edilen kayda önizleme yazılır")
    func processingStoresThumbnail() async throws {
        let source = FakeShotSource(assets: assets(1, from: epoch))
        let index = FakeIndex()
        let pipeline = makePipeline(source: source, index: index)
        try await pipeline.synchronizeLibrary()

        await pipeline.processPending()

        #expect(await index.thumbnails["asset-0"] != nil)
        // Önizleme ve analiz görselinin boyutu farklı istenmeli.
        let sizes = Set(await source.imageRequests.map(\.maxPixelSize))
        #expect(sizes.contains(AnalysisPipeline.analysisPixelSize))
        #expect(sizes.contains(AnalysisPipeline.thumbnailPixelSize))
    }

    @Test("Kalıcı hata kaydı failed işaretler, kuyruktan düşürür")
    func permanentFailureMarksFailed() async throws {
        let source = FakeShotSource(assets: assets(1, from: epoch))
        await source.setFailing(["asset-0"], error: AppError(.notFound, "görsel yok"))
        let index = FakeIndex()
        let pipeline = makePipeline(source: source, index: index)
        try await pipeline.synchronizeLibrary()

        let processed = await pipeline.processPending()

        #expect(processed == 0)
        #expect(await index.storage["asset-0"]?.status == .failed(reason: "görsel yok"))
        #expect(try await index.pendingAssetIdentifiers(limit: 10).isEmpty)
    }

    @Test("Geçici hata kaydı pending bırakır, yeniden denenir")
    func transientFailureStaysPending() async throws {
        // Yalnız iCloud'da duran görsel bugün analiz edilemez ama yarın edilebilir (KANON §1).
        let source = FakeShotSource(assets: assets(1, from: epoch))
        await source.setFailing(["asset-0"], error: AppError(.transient, "yalnız iCloud'da"))
        let index = FakeIndex()
        let pipeline = makePipeline(source: source, index: index)
        try await pipeline.synchronizeLibrary()

        await pipeline.processPending()

        #expect(await index.storage["asset-0"]?.status == .pending)
        #expect(try await index.pendingAssetIdentifiers(limit: 10) == ["asset-0"])
    }

    @Test("Analiz hatası diğer kayıtları durdurmaz")
    func oneFailureDoesNotStopTheBatch() async throws {
        let source = FakeShotSource(assets: assets(4, from: epoch))
        await source.setFailing(["asset-2"], error: AppError(.invalidInput, "bozuk"))
        let index = FakeIndex()
        let pipeline = makePipeline(source: source, index: index)
        try await pipeline.synchronizeLibrary()

        #expect(await pipeline.processPending() == 3)
    }

    @Test("İşlenecek kayıt yoksa sıfır döner")
    func emptyQueueReturnsZero() async {
        let pipeline = makePipeline(source: FakeShotSource(), index: FakeIndex())
        #expect(await pipeline.processPending() == 0)
    }

    @Test("İlerleme akışı analiz sonrası güncellenir")
    func progressStreamReportsCounts() async throws {
        let source = FakeShotSource(assets: assets(2, from: epoch))
        let index = FakeIndex()
        let pipeline = makePipeline(source: source, index: index)

        var iterator = await pipeline.progress().makeAsyncIterator()
        try await pipeline.synchronizeLibrary()

        let afterSync = await iterator.next()
        #expect(afterSync?.total == 2)
        #expect(afterSync?.analyzed == 0)

        await pipeline.processPending()
        let afterProcessing = await iterator.next()
        #expect(afterProcessing?.analyzed == 2)
        #expect(afterProcessing?.fraction == 1)
    }
}
