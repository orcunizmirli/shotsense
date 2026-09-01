import Foundation
import ShotCore
import SwiftData

/// `Shot`'ın SwiftData karşılığı.
///
/// Domain tipi (`ShotCore.Shot`) ile ayrı tutulur (05 §3): domain SwiftData bilmez, bu
/// yüzden domain testleri veri deposu kurmadan koşar.
///
/// **Depolama kararları:**
/// - Enum'lar ham `String` olarak saklanır. SwiftData `RawRepresentable` enum'ları
///   destekler ama ilişkilendirilmiş değerli `AnalysisStatus` desteklenmez; iki alanı da
///   aynı biçimde tutmak şema göçlerini öngörülebilir kılar.
/// - Varlıklar ayrı bir `@Model` yerine **JSON blob** olarak saklanır. Varlıklar her zaman
///   kaydın tamamıyla birlikte okunur, hiçbir zaman tek başına sorgulanmaz; ayrı tablo
///   yalnız ilişki göçü maliyeti getirirdi.
@Model
public final class ShotRecord {
    #Unique<ShotRecord>([\.assetIdentifier])

    public var assetIdentifier: String = ""
    public var createdAt: Date = Date(timeIntervalSince1970: 0)
    public var indexedAt: Date?

    /// `AnalysisStatus` ham değeri: pending | analyzing | analyzed | failed | orphaned
    public var statusRaw: String = "pending"
    /// Yalnız `failed` durumunda dolu.
    public var failureReason: String?
    public var schemaVersion: Int = AnalysisSchema.currentVersion

    public var recognizedText: String = ""
    public var ocrLanguages: [String] = []
    public var barcodePayloads: [String] = []

    public var categoryRaw: String = ShotCategory.other.rawValue
    public var categoryConfidence: Double = 0
    public var title: String = ""
    public var summary: String = ""
    public var tags: [String] = []
    public var analyzerKindRaw: String = AnalyzerKind.heuristic.rawValue
    public var userCorrected: Bool = false

    /// `[ExtractedEntity]` JSON'u.
    public var entitiesData: Data = Data()
    /// Normalize edilmiş cümle vektörü; model yoksa nil.
    public var embedding: [Float]?
    /// 320 px JPEG önizleme.
    @Attribute(.externalStorage) public var thumbnailData: Data?

    /// Kaç kez analiz denendi — kalıcı kuyruk geri çekilmesi bunu kullanır (03 §6).
    public var analysisAttempts: Int = 0

    public init(assetIdentifier: String, createdAt: Date) {
        self.assetIdentifier = assetIdentifier
        self.createdAt = createdAt
    }
}

/// SwiftData sürümlenmiş şeması. Alan eklemek/çıkarmak yeni bir sürüm ve göç planı gerektirir (05 §5).
public enum ShotSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [ShotRecord.self] }
}
