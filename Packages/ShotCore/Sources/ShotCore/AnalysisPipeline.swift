import AppFoundation
import Foundation

/// İndeksleme ilerlemesi — arayüzdeki ilerleme bandı bunu dinler (02 §2.2).
public struct IndexingProgress: Sendable, Hashable {
    public let analyzed: Int
    public let total: Int
    public let isRunning: Bool

    public init(analyzed: Int, total: Int, isRunning: Bool) {
        self.analyzed = analyzed
        self.total = total
        self.isRunning = isRunning
    }

    public var fraction: Double {
        total > 0 ? min(Double(analyzed) / Double(total), 1) : 0
    }
}

/// Bir ekran görüntüsünün keşiften indekse uzanan yolculuğunu yürüten orkestratör (03 §6).
///
/// **Neden domain'de:** yalnız portlara bağlıdır — Vision, Photos, SwiftData veya
/// FoundationModels tiplerine değil. Bu sayede tüm akış (öncelik, geri çekilme, iptal,
/// Free katman sınırı) sahte portlarla, simülatörsüz test edilebilir.
///
/// `actor` olması kuyruğun tek sahibi olmasını sağlar: ön planda kullanıcı bir görsele
/// dokunduğunda onu öne almak, arka planda toplu işlemek ve ikisinin çakışmaması gerekir.
public actor AnalysisPipeline {
    private let source: any ShotSourcing
    private let recognizer: any TextRecognizing
    private let analyzer: any ShotAnalyzing
    private let index: any ShotIndexing
    private let dateProvider: any DateProviding

    /// Eşzamanlı analiz sayısı. Ön planda 2: OCR ve LLM ikisi de Neural Engine'i kullanır,
    /// daha fazlası hem hızlandırmaz hem arayüzü takar (03 §7).
    private let concurrency: Int
    /// Free katmanda yalnız en yeni N görsel indekslenir; `nil` = sınırsız (Pro).
    private var indexLimit: Int?

    private var isRunning = false
    private var progressContinuations: [UUID: AsyncStream<IndexingProgress>.Continuation] = [:]

    public init(
        source: any ShotSourcing,
        recognizer: any TextRecognizing,
        analyzer: any ShotAnalyzing,
        index: any ShotIndexing,
        dateProvider: any DateProviding = SystemDateProvider(),
        concurrency: Int = 2,
        indexLimit: Int? = FreeTierLimits.indexedShotCount
    ) {
        self.source = source
        self.recognizer = recognizer
        self.analyzer = analyzer
        self.index = index
        self.dateProvider = dateProvider
        self.concurrency = max(1, concurrency)
        self.indexLimit = indexLimit
    }

    /// Abonelik durumu değiştiğinde çağrılır: Pro olunca sınır kalkar, biterse geri gelir.
    public func updateIndexLimit(_ limit: Int?) {
        indexLimit = limit
    }

    // MARK: - İlerleme

    public func progress() -> AsyncStream<IndexingProgress> {
        AsyncStream { continuation in
            let id = UUID()
            progressContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeProgressContinuation(id) }
            }
        }
    }

    private func removeProgressContinuation(_ id: UUID) {
        progressContinuations[id] = nil
    }

    private func publishProgress() async {
        guard let counts = try? await index.counts() else { return }
        let progress = IndexingProgress(
            analyzed: counts.analyzed, total: counts.total, isRunning: isRunning
        )
        for continuation in progressContinuations.values {
            continuation.yield(progress)
        }
    }

    // MARK: - Keşif

    /// Fotoğraf kitaplığını tarar, yeni ekran görüntüleri için `pending` kayıt açar ve
    /// silinmiş olanları temizler.
    ///
    /// - Returns: kuyruğa eklenen yeni kayıt sayısı.
    @discardableResult
    public func synchronizeLibrary() async throws -> Int {
        let authorization = await source.authorizationStatus
        guard authorization == .authorized || authorization == .limited else {
            throw AppError(.permissionDenied, "Fotoğraf erişimi yok")
        }

        let assets = try await source.screenshots(newerThan: nil)
        // Free katmanda yalnız en yeni N görsel: liste zaten yeniden eskiye sıralı.
        let eligible = indexLimit.map { Array(assets.prefix($0)) } ?? assets

        let existing = try await existingIdentifiers()
        let new = eligible.filter { !existing.contains($0.identifier) }

        if !new.isEmpty {
            try await index.upsert(
                new.map { Shot(assetIdentifier: $0.identifier, createdAt: $0.createdAt) }
            )
        }

        // Photos'tan silinmiş kayıtlar yetim kalır; sessizce temizlenir (05 §6).
        let liveIdentifiers = Set(assets.map(\.identifier))
        let orphaned = existing.subtracting(liveIdentifiers)
        if !orphaned.isEmpty {
            try await index.remove(assetIdentifiers: Array(orphaned))
            Log.info(.ingest, "Yetim kayıt temizlendi", detail: "\(orphaned.count) adet")
        }

        await publishProgress()
        return new.count
    }

    private func existingIdentifiers() async throws -> Set<String> {
        // Port kimlik kümesi vermez; sayfalı okumayla toplanır. Kitaplık boyutu bilinen
        // sınırlar içinde (binler) olduğu için bu tek seferlik tarama kabul edilebilir.
        var identifiers = Set<String>()
        var offset = 0
        let page = 500
        while true {
            let batch = try await index.shots(category: nil, limit: page, offset: offset)
            if batch.isEmpty { break }
            identifiers.formUnion(batch.map(\.assetIdentifier))
            if batch.count < page { break }
            offset += page
        }
        return identifiers
    }

    // MARK: - İşleme

    /// Bekleyen kayıtları işler.
    ///
    /// - Parameter limit: bu turda işlenecek en fazla kayıt. Arka plan görevi kısa tutulmalıdır
    ///   (sistem `BGProcessingTask`'ı sonlandırabilir), bu yüzden çağıran küçük partiler ister.
    @discardableResult
    public func processPending(limit: Int = 50) async -> Int {
        guard !isRunning else { return 0 }
        isRunning = true
        defer { isRunning = false }

        guard let identifiers = try? await index.pendingAssetIdentifiers(limit: limit),
              !identifiers.isEmpty
        else {
            await publishProgress()
            return 0
        }

        var processed = 0
        var remaining = identifiers[...]

        await withTaskGroup(of: Bool.self) { group in
            // Sabit boyutlu pencere: tüm kuyruğu aynı anda başlatmak belleği ve Neural
            // Engine'i boğar. Biten her görevin yerine yenisi alınır.
            for _ in 0 ..< min(concurrency, remaining.count) {
                guard let next = remaining.popFirst() else { break }
                group.addTask { [weak self] in
                    await self?.process(assetIdentifier: next) ?? false
                }
            }

            while let succeeded = await group.next() {
                if succeeded { processed += 1 }
                if let next = remaining.popFirst() {
                    group.addTask { [weak self] in
                        await self?.process(assetIdentifier: next) ?? false
                    }
                }
            }
        }

        await publishProgress()
        Log.info(.index, "Parti tamamlandı", detail: "\(processed)/\(identifiers.count)")
        return processed
    }

    /// Tek bir ekran görüntüsünün tam zinciri. Hata hâlinde kayıt `failed` işaretlenir ama
    /// **metin yine indekslenir**: analiz başarısız olsa da arama çalışmaya devam eder.
    @discardableResult
    public func process(assetIdentifier: String) async -> Bool {
        guard let existing = try? await index.shot(assetIdentifier: assetIdentifier) else {
            return false
        }

        do {
            let imageData = try await source.imageData(
                for: assetIdentifier, maxPixelSize: AnalysisPipeline.analysisPixelSize
            )
            let document = try await recognizer.recognize(imageData: imageData, languages: [])
            let analysis = try await analyzer.analyze(document)

            try await index.upsert(
                Shot(
                    assetIdentifier: assetIdentifier,
                    createdAt: existing.createdAt,
                    indexedAt: dateProvider.now,
                    status: .analyzed,
                    schemaVersion: AnalysisSchema.currentVersion,
                    recognizedText: document.fullText,
                    ocrLanguages: document.languages,
                    barcodePayloads: document.barcodes.map(\.payload),
                    analysis: analysis,
                    userCorrected: existing.userCorrected
                )
            )
            await storeThumbnail(for: assetIdentifier)
            return true
        } catch {
            await recordFailure(error, for: assetIdentifier, existing: existing)
            return false
        }
    }

    private func storeThumbnail(for assetIdentifier: String) async {
        guard (try? await index.thumbnail(for: assetIdentifier)) == nil else { return }
        guard let data = try? await source.imageData(
            for: assetIdentifier, maxPixelSize: AnalysisPipeline.thumbnailPixelSize
        ) else { return }
        try? await index.setThumbnail(data, for: assetIdentifier)
    }

    private func recordFailure(_ error: any Error, for assetIdentifier: String, existing: Shot) async {
        let appError = error as? AppError
        // Geçici hatalarda (ör. görsel yalnız iCloud'da) kayıt `pending` kalır ve sonraki
        // turda yeniden denenir; kalıcı hatalarda `failed` işaretlenir ve kuyruktan düşer.
        let status: AnalysisStatus = (appError?.isRetryable ?? false)
            ? .pending
            : .failed(reason: appError?.debugMessage ?? "analiz başarısız")

        Log.warning(
            .index,
            "Analiz başarısız",
            detail: appError?.debugMessage ?? String(describing: type(of: error))
        )
        try? await index.upsert(
            Shot(
                assetIdentifier: assetIdentifier,
                createdAt: existing.createdAt,
                status: status,
                recognizedText: existing.recognizedText,
                analysis: existing.analysis,
                userCorrected: existing.userCorrected
            )
        )
    }

    /// OCR'a giren görselin uzun kenarı (03 §7).
    public static let analysisPixelSize = 2048
    /// Kitaplık önizlemesinin uzun kenarı.
    public static let thumbnailPixelSize = 320
}
