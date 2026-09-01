import AppFoundation
import IntelligenceKit
import ShotCore

/// Kullanıcı ayarına ve cihaz yeteneğine göre analiz yolunu **her çağrıda** seçen sarmalayıcı.
///
/// Kompozisyon kökünde durur çünkü iki adaptörü birlikte görür — hiçbir paket bunu yapamaz (R2).
///
/// **Neden her çağrıda kontrol:** iki durum uygulama ömrü içinde değişir. Kullanıcı Ayarlar'dan
/// "Akıllı analiz"i kapatabilir, ve Apple Intelligence modeli arka planda indirilmeyi
/// bitirebilir (`modelNotReady` → `available`). Açılışta bir kez karar vermek, ilk durumda
/// kullanıcının tercihini yok sayar, ikincisinde ise modeli hiç kullanmadan kitaplığı bitirir.
/// Kontrolün maliyeti bir özellik okumasıdır; analizin kendisi yanında ölçülemez.
struct SettingsAwareAnalyzer: ShotAnalyzing {
    let kind: AnalyzerKind = .foundationModel

    private let foundationModel = FoundationModelAnalyzer()
    private let heuristic = HeuristicAnalyzer()
    private let settings: any SettingsStoring

    init(settings: any SettingsStoring) {
        self.settings = settings
    }

    var isAvailable: Bool {
        get async { true } // Heuristik yol her zaman var (KANON §5).
    }

    func analyze(_ document: RecognizedDocument) async throws -> ShotAnalysis {
        if await useIntelligence() {
            return try await foundationModel.analyze(document)
        }
        return try await heuristic.analyze(document)
    }

    func parseSearchIntent(_ query: String) async -> SearchIntent {
        if await useIntelligence() {
            return await foundationModel.parseSearchIntent(query)
        }
        return await heuristic.parseSearchIntent(query)
    }

    private func useIntelligence() async -> Bool {
        guard await settings.flags().intelligenceEnabled else { return false }
        return await foundationModel.isAvailable
    }
}
