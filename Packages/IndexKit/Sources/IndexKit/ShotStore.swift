import AppFoundation
import Foundation
import ShotCore
import SwiftData

/// Kaydın arama sıcak yolunda ihtiyaç duyulan hafif özeti.
///
/// Tam `Shot` OCR metnini de taşır (ortalama ~2 KB); 5.000 kaydı her aramada tam hâlleriyle
/// belleğe açmak hem yavaş hem gereksizdir. Süzme ve sıralama bu tiple yapılır, yalnız
/// kazanan ~60 kaydın tamamı okunur.
public struct IndexedDocument: Sendable, ShotFilterable {
    public let assetIdentifier: String
    public let createdAt: Date
    public let category: ShotCategory
    public let amounts: [Double]
    public let title: String
    public let summary: String
    public let tags: [String]
    public let embedding: [Float]?

    public var filterCategory: ShotCategory { category }
    public var filterCreatedAt: Date { createdAt }
    public var filterAmounts: [Double] { amounts }
}

/// BM25 indeksini kurmak için gereken ham metin.
///
/// İsimsiz demet yerine tip: dört alanlı bir demet çağrı yerinde okunmaz hâle gelir ve
/// alan sırası değişince derleyici sessizce kabul eder.
public struct IndexingPayload: Sendable {
    public let identifier: String
    public let title: String
    public let body: String
    public let tags: [String]
}

/// SwiftData erişiminin tek noktası.
///
/// `@ModelActor` ile izole edilir: Swift 6'da `ModelContext` `Sendable` değildir ve birden
/// çok context'ten yazmak SwiftData'da veri yarışına yol açar. Tüm yazmalar buradan geçer (03 §5).
@ModelActor
public actor ShotStore {
    // MARK: - Yazma

    public func upsert(_ shots: [Shot]) throws {
        for shot in shots {
            let record: ShotRecord
            if let existing = try existingRecord(for: shot.assetIdentifier) {
                record = existing
            } else {
                record = ShotRecord(
                    assetIdentifier: shot.assetIdentifier, createdAt: shot.createdAt
                )
                modelContext.insert(record)
            }
            ShotMapper.apply(shot, to: record)
        }
        try modelContext.save()
    }

    public func setThumbnail(_ data: Data, for assetIdentifier: String) throws {
        guard let record = try existingRecord(for: assetIdentifier) else { return }
        record.thumbnailData = data
        try modelContext.save()
    }

    public func thumbnail(for assetIdentifier: String) throws -> Data? {
        try existingRecord(for: assetIdentifier)?.thumbnailData
    }

    public func markAttempt(for assetIdentifier: String) throws {
        guard let record = try existingRecord(for: assetIdentifier) else { return }
        record.analysisAttempts += 1
        try modelContext.save()
    }

    public func remove(assetIdentifiers: [String]) throws {
        for identifier in assetIdentifiers {
            if let record = try existingRecord(for: identifier) {
                modelContext.delete(record)
            }
        }
        try modelContext.save()
    }

    /// Türev veriyi siler; Photos'taki görsellere dokunmaz (05 §6).
    public func reset() throws {
        try modelContext.delete(model: ShotRecord.self)
        try modelContext.save()
        Log.info(.index, "İndeks sıfırlandı")
    }

    // MARK: - Okuma

    public func shot(assetIdentifier: String) throws -> Shot? {
        try existingRecord(for: assetIdentifier).map(ShotMapper.domain)
    }

    public func shots(assetIdentifiers: [String]) throws -> [Shot] {
        // Predicate içinde Array.contains desteklenir; Set desteklenmez.
        let wanted = assetIdentifiers
        let descriptor = FetchDescriptor<ShotRecord>(
            predicate: #Predicate { wanted.contains($0.assetIdentifier) }
        )
        return try modelContext.fetch(descriptor).map(ShotMapper.domain)
    }

    public func shots(category: ShotCategory?, limit: Int, offset: Int) throws -> [Shot] {
        var descriptor = FetchDescriptor<ShotRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let category {
            let raw = category.rawValue
            descriptor.predicate = #Predicate { $0.categoryRaw == raw }
        }
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return try modelContext.fetch(descriptor).map(ShotMapper.domain)
    }

    /// Arama indeksini kurmak için tüm kayıtların hafif özeti.
    public func allDocuments() throws -> [IndexedDocument] {
        let descriptor = FetchDescriptor<ShotRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { record in
            IndexedDocument(
                assetIdentifier: record.assetIdentifier,
                createdAt: record.createdAt,
                category: ShotCategory(rawValue: record.categoryRaw) ?? .other,
                amounts: ShotMapper.entities(from: record.entitiesData)
                    .filter(\.isGrounded)
                    .compactMap(\.amountValue),
                title: record.title,
                summary: record.summary,
                tags: record.tags,
                embedding: record.embedding
            )
        }
    }

    /// Arama için gereken tam metin; indeks kurulurken tek seferde okunur.
    public func indexingPayloads() throws -> [IndexingPayload] {
        let descriptor = FetchDescriptor<ShotRecord>()
        return try modelContext.fetch(descriptor).map { record in
            IndexingPayload(
                identifier: record.assetIdentifier,
                title: record.title,
                body: record.recognizedText + "\n" + record.summary,
                tags: record.tags
            )
        }
    }

    public func recognizedText(for assetIdentifier: String) throws -> String {
        try existingRecord(for: assetIdentifier)?.recognizedText ?? ""
    }

    /// Analiz bekleyenler: önce hiç denenmemişler, sonra en yeni kayıtlar.
    ///
    /// Sıra kullanıcı algısı için önemlidir: kitaplığı açan kullanıcı en yeni ekran
    /// görüntülerinin analiz edilmiş olmasını bekler, 2019'dan kalanların değil.
    public func pendingIdentifiers(limit: Int, maximumAttempts: Int = 3) throws -> [String] {
        var descriptor = FetchDescriptor<ShotRecord>(
            predicate: #Predicate { $0.statusRaw != "analyzed" && $0.statusRaw != "orphaned" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit * 4
        return try modelContext.fetch(descriptor)
            .filter { $0.analysisAttempts < maximumAttempts }
            .prefix(limit)
            .map(\.assetIdentifier)
    }

    /// Şeması eskimiş, yeniden analiz edilmesi gereken kayıtlar (05 §5).
    public func staleIdentifiers(limit: Int) throws -> [String] {
        let current = AnalysisSchema.currentVersion
        var descriptor = FetchDescriptor<ShotRecord>(
            predicate: #Predicate { $0.statusRaw == "analyzed" && $0.schemaVersion < current },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(\.assetIdentifier)
    }

    public func knownIdentifiers() throws -> Set<String> {
        Set(try modelContext.fetch(FetchDescriptor<ShotRecord>()).map(\.assetIdentifier))
    }

    public func counts() throws -> IndexCounts {
        let records = try modelContext.fetch(FetchDescriptor<ShotRecord>())
        var analyzed = 0
        var pending = 0
        var failed = 0
        for record in records {
            switch record.statusRaw {
            case "analyzed": analyzed += 1
            case "failed": failed += 1
            case "orphaned": break
            default: pending += 1
            }
        }
        return IndexCounts(
            total: analyzed + pending + failed, analyzed: analyzed, pending: pending, failed: failed
        )
    }

    // MARK: - Yardımcı

    private func existingRecord(for assetIdentifier: String) throws -> ShotRecord? {
        var descriptor = FetchDescriptor<ShotRecord>(
            predicate: #Predicate { $0.assetIdentifier == assetIdentifier }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
