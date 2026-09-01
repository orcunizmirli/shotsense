import AppFoundation
import Foundation
import ShotCore

/// `ShotRecord` ↔ `Shot` dönüşümü. Tek yönlü kural: domain tipi kaynak, kayıt türev.
enum ShotMapper {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func domain(from record: ShotRecord) -> Shot {
        Shot(
            assetIdentifier: record.assetIdentifier,
            createdAt: record.createdAt,
            indexedAt: record.indexedAt,
            status: status(raw: record.statusRaw, reason: record.failureReason),
            schemaVersion: record.schemaVersion,
            recognizedText: record.recognizedText,
            ocrLanguages: record.ocrLanguages,
            barcodePayloads: record.barcodePayloads,
            analysis: ShotAnalysis(
                category: ShotCategory(rawValue: record.categoryRaw) ?? .other,
                categoryConfidence: record.categoryConfidence,
                title: record.title,
                summary: record.summary,
                tags: record.tags,
                entities: entities(from: record.entitiesData),
                analyzerKind: AnalyzerKind(rawValue: record.analyzerKindRaw) ?? .heuristic
            ),
            userCorrected: record.userCorrected
        )
    }

    static func apply(_ shot: Shot, to record: ShotRecord) {
        record.createdAt = shot.createdAt
        record.indexedAt = shot.indexedAt
        record.schemaVersion = shot.schemaVersion
        record.recognizedText = shot.recognizedText
        record.ocrLanguages = shot.ocrLanguages
        record.barcodePayloads = shot.barcodePayloads
        record.categoryRaw = shot.analysis.category.rawValue
        record.categoryConfidence = shot.analysis.categoryConfidence
        record.title = shot.analysis.title
        record.summary = shot.analysis.summary
        record.tags = shot.analysis.tags
        record.analyzerKindRaw = shot.analysis.analyzerKind.rawValue
        record.userCorrected = shot.userCorrected
        record.entitiesData = encode(shot.analysis.entities)

        switch shot.status {
        case .pending:
            record.statusRaw = "pending"
            record.failureReason = nil
        case .analyzing:
            record.statusRaw = "analyzing"
            record.failureReason = nil
        case .analyzed:
            record.statusRaw = "analyzed"
            record.failureReason = nil
        case let .failed(reason):
            record.statusRaw = "failed"
            record.failureReason = reason
        case .orphaned:
            record.statusRaw = "orphaned"
            record.failureReason = nil
        }
    }

    static func status(raw: String, reason: String?) -> AnalysisStatus {
        switch raw {
        case "analyzing": return .analyzing
        case "analyzed": return .analyzed
        case "failed": return .failed(reason: reason ?? "bilinmiyor")
        case "orphaned": return .orphaned
        default: return .pending
        }
    }

    static func encode(_ entities: [ExtractedEntity]) -> Data {
        (try? encoder.encode(entities)) ?? Data()
    }

    static func entities(from data: Data) -> [ExtractedEntity] {
        guard !data.isEmpty else { return [] }
        do {
            return try decoder.decode([ExtractedEntity].self, from: data)
        } catch {
            // Şema değişikliğinden sonra eski blob çözülemeyebilir; kayıt kaybolmasın diye
            // varlıklar boş döner ve yeniden analiz kuyruğu onları tekrar üretir.
            Log.warning(.index, "Varlık blob'u çözülemedi, yeniden analiz gerekecek")
            return []
        }
    }
}
