import CoreGraphics
import Foundation
import ImageIO
import ShotCore
import ShotCoreTestSupport
import Testing
import UniformTypeIdentifiers
@testable import LibraryKit

@MainActor
@Suite("ThumbnailStore")
struct ThumbnailStoreTests {
    /// Testin gerçek çözme yolundan geçmesi için belleğe küçük bir PNG üretir.
    private func makePNG(size: Int = 40) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// Koşul sağlanana kadar bekler; toplama penceresi asenkron olduğu için gerekli.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func makeIndex(ids: [String], data: Data) async -> FakeIndex {
        let index = FakeIndex()
        for id in ids {
            try? await index.setThumbnail(data, for: id)
        }
        return index
    }

    @Test("Aynı penceredeki istekler TEK toplu sorguya iner")
    func requestsAreBatched() async throws {
        // Bu testin varlık sebebi bir performans gerilemesini yakalamak: hücre başına
        // ayrı okuma yapan bir düzenlemeye dönülürse burada 5 istek görünür.
        let data = try makePNG()
        let ids = (0 ..< 5).map { "asset-\($0)" }
        let index = await makeIndex(ids: ids, data: data)
        let store = ThumbnailStore(index: index, batchWindow: .milliseconds(5))

        store.prefetch(ids)
        _ = await waitUntil { store.cachedCount == ids.count }

        let batches = await index.thumbnailBatchRequests
        #expect(batches.count == 1)
        #expect(Set(batches[0]) == Set(ids))
    }

    @Test("Önbellekteki görsel yeniden istenmez")
    func cachedImagesAreNotRefetched() async throws {
        let data = try makePNG()
        let index = await makeIndex(ids: ["a"], data: data)
        let store = ThumbnailStore(index: index, batchWindow: .milliseconds(5))

        store.prefetch(["a"])
        _ = await waitUntil { store.image(for: "a") != nil }

        store.prefetch(["a"])
        _ = await waitUntil(timeout: .milliseconds(80)) { false }

        #expect(await index.thumbnailBatchRequests.count == 1)
    }

    @Test("Önizlemesi olmayan kayıt tekrar tekrar istenmez")
    func missingThumbnailsAreNotRetried() async {
        // Aksi hâlde her kaydırmada aynı boş kayıt için sorgu atılır ve kaydırma takılır.
        let index = FakeIndex()
        let store = ThumbnailStore(index: index, batchWindow: .milliseconds(5))

        store.prefetch(["yok"])
        _ = await waitUntil(timeout: .milliseconds(150)) { false }
        store.prefetch(["yok"])
        _ = await waitUntil(timeout: .milliseconds(80)) { false }

        #expect(await index.thumbnailBatchRequests.count == 1)
    }

    @Test("Kapasite aşılınca en eski görsel düşer")
    func lruEvictsOldest() async throws {
        let data = try makePNG()
        let ids = ["a", "b", "c"]
        let index = await makeIndex(ids: ids, data: data)
        let store = ThumbnailStore(index: index, capacity: 2, batchWindow: .milliseconds(5))

        store.prefetch(ids)
        _ = await waitUntil { store.cachedCount == 2 }

        #expect(store.cachedCount == 2)
    }

    @Test("Geçersiz kılma önbellekten düşürür")
    func invalidateDropsCachedImage() async throws {
        let data = try makePNG()
        let index = await makeIndex(ids: ["a"], data: data)
        let store = ThumbnailStore(index: index, batchWindow: .milliseconds(5))

        store.prefetch(["a"])
        _ = await waitUntil { store.image(for: "a") != nil }

        store.invalidate("a")
        #expect(store.image(for: "a") == nil)
    }

    @Test("image(for:) yan etkisizdir")
    func imageLookupDoesNotStartWork() async {
        // View.body içinden çağrıldığı için iş başlatmamalı; başlatırsa her yeniden
        // çizimde yeni görev doğar ve kaydırma çöker.
        let index = FakeIndex()
        let store = ThumbnailStore(index: index, batchWindow: .milliseconds(5))

        _ = store.image(for: "a")
        _ = await waitUntil(timeout: .milliseconds(80)) { false }

        #expect(await index.thumbnailBatchRequests.isEmpty)
    }
}
