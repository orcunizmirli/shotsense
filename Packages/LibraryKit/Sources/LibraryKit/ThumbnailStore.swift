import AppFoundation
import CoreGraphics
import DesignSystem
import Foundation
import ShotCore

/// Izgara önizlemelerinin bellek-içi önbelleği, toplayıcısı ve çözücüsü.
///
/// Kaydırma akıcılığının tamamı bu tipte toplanır. Üç sorunu birlikte çözer:
///
/// 1. **Gidiş-dönüş patlaması.** Hücre başına `index.thumbnail(for:)` çağırmak, veri
///    deposu aktörüne görünen hücre sayısı kadar ayrı istek demektir; hepsi tek aktörde
///    sıraya girer. Burada istekler kısa bir pencerede **toplanır** ve tek toplu sorguya
///    dönüşür.
/// 2. **Ana iş parçacığında çözme.** JPEG çözme hücre çiziminde yapılırsa kare düşer.
///    Çözme arka planda ve **görüntüleme boyutunda** yapılır.
/// 3. **Bellek.** Sınırsız önbellek 5.000 görselde uygulamayı sonlandırır. LRU ile
///    sabit bir tavan tutulur.
///
/// Ayrıca **ön yükleme** yapar: kullanıcı bir hücreye ulaştığında sonraki hücrelerin
/// görselleri çoktan istenmiştir, bu yüzden kaydırırken boş kare görülmez.
@MainActor
@Observable
public final class ThumbnailStore {
    /// Bellekte tutulan en fazla çözülmüş görsel.
    ///
    /// 320 px'lik bir önizleme ~230 KB tutar; 150 görsel ≈ 35 MB. Bu, ızgarada
    /// hızlı kaydırma sırasında geriye dönüşleri anında yapmaya yeter ve arka plana
    /// atılan uygulamanın sonlandırılma riskini artırmaz.
    private let capacity: Int
    /// Çözme hedefi (piksel). Depodaki önizleme 320 px; ekran ölçeğiyle birlikte
    /// hücreye sığacak en küçük değer seçilir.
    private let decodePixelSize: Int
    /// İsteklerin toplanma penceresi. Bir kaydırma darbesinde onlarca hücre görünür;
    /// 30 ms hepsini tek partide toplamaya yeter ve gecikme olarak hissedilmez.
    private let batchWindow: Duration

    private let index: any ShotIndexing

    private var cache: [String: CGImage] = [:]
    /// En son kullanılandan en eskiye; LRU tahliyesi buradan yapılır.
    private var recency: [String] = []
    /// Partiye alınmayı bekleyenler.
    private var queued: Set<String> = []
    /// Şu an okunuyor/çözülüyor olanlar — aynı görsel iki kez istenmez.
    private var inFlight: Set<String> = []
    /// Önizlemesi olmayan kayıtlar; sonsuz yeniden istek döngüsünü önler.
    private var missing: Set<String> = []
    private var flushTask: Task<Void, Never>?

    public init(
        index: any ShotIndexing,
        capacity: Int = 150,
        decodePixelSize: Int = 360,
        batchWindow: Duration = .milliseconds(30)
    ) {
        self.index = index
        self.capacity = max(1, capacity)
        self.decodePixelSize = decodePixelSize
        self.batchWindow = batchWindow
    }

    // MARK: - Okuma

    /// Önbellekteki görsel. Yoksa `nil` — çağıran ayrıca `prefetch` çağırmalıdır.
    ///
    /// Bu fonksiyon **hiçbir iş başlatmaz**: `View.body` içinden çağrıldığı için yan
    /// etkisiz olmak zorundadır.
    public func image(for assetIdentifier: String) -> CGImage? {
        cache[assetIdentifier]
    }

    // MARK: - Ön yükleme

    /// Verilen kimlikleri kuyruğa alır; kısa bir pencere sonra tek partide okunur.
    public func prefetch(_ assetIdentifiers: some Sequence<String>) {
        var didQueue = false
        for identifier in assetIdentifiers {
            guard cache[identifier] == nil,
                  !inFlight.contains(identifier),
                  !missing.contains(identifier)
            else {
                touch(identifier)
                continue
            }
            queued.insert(identifier)
            didQueue = true
        }
        guard didQueue else { return }
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: self?.batchWindow ?? .milliseconds(30))
            await self?.flush()
        }
    }

    private func flush() async {
        flushTask = nil
        let batch = queued
        queued.removeAll()
        guard !batch.isEmpty else { return }

        inFlight.formUnion(batch)
        defer { inFlight.subtract(batch) }

        let identifiers = Array(batch)
        guard let payloads = try? await index.thumbnails(for: identifiers) else { return }

        // Önizlemesi olmayanlar işaretlenir: aksi hâlde her kaydırmada yeniden istenirler.
        missing.formUnion(batch.subtracting(payloads.keys))

        let pixelSize = decodePixelSize
        let decoded = await Self.decode(payloads, maxPixelSize: pixelSize)
        for (identifier, image) in decoded {
            insert(image, for: identifier)
        }

        // Parti işlenirken yeni istekler birikmiş olabilir.
        if !queued.isEmpty { scheduleFlush() }
    }

    /// Partiyi ana iş parçacığı dışında, paralel çözer.
    private static func decode(
        _ payloads: [String: Data],
        maxPixelSize: Int
    ) async -> [String: CGImage] {
        await withTaskGroup(of: (String, CGImage?).self) { group in
            for (identifier, data) in payloads {
                group.addTask(priority: .userInitiated) {
                    (identifier, ImageDecoding.decode(data, maxPixelSize: maxPixelSize))
                }
            }
            var result: [String: CGImage] = [:]
            for await (identifier, image) in group {
                if let image { result[identifier] = image }
            }
            return result
        }
    }

    // MARK: - Önbellek yönetimi

    private func insert(_ image: CGImage, for identifier: String) {
        cache[identifier] = image
        touch(identifier)
        evictIfNeeded()
    }

    private func touch(_ identifier: String) {
        guard cache[identifier] != nil else { return }
        if let existing = recency.firstIndex(of: identifier) {
            recency.remove(at: existing)
        }
        recency.append(identifier)
    }

    private func evictIfNeeded() {
        while recency.count > capacity {
            let oldest = recency.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    /// Kayıt güncellendiğinde (yeniden analiz, yeni önizleme) çağrılır.
    public func invalidate(_ assetIdentifier: String) {
        cache.removeValue(forKey: assetIdentifier)
        missing.remove(assetIdentifier)
        recency.removeAll { $0 == assetIdentifier }
    }

    public func removeAll() {
        cache.removeAll()
        recency.removeAll()
        queued.removeAll()
        missing.removeAll()
        flushTask?.cancel()
        flushTask = nil
    }

    // MARK: - Test gözlemi

    /// Önbellekteki görsel sayısı — LRU davranışını doğrulamak için.
    public var cachedCount: Int { cache.count }
}
