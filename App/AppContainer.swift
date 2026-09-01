import ActionKit
import AppFoundation
import IndexKit
import IngestKit
import IntelligenceKit
import LibraryKit
import OCRKit
import PaywallKit
import ShotCore
import SwiftData
import SwiftUI

/// **Kompozisyon kökü** (03 §1): adaptörlerin portlara bağlandığı tek yer.
///
/// Bu dosya, uygulamada `OCRKit`, `IngestKit`, `IndexKit`, `IntelligenceKit`, `ActionKit` ve
/// `PaywallKit`'i **birlikte** gören yegâne dosyadır. Arayüz ve domain yalnız protokolleri
/// görür; hangi gerçeklemenin bağlandığını bilmezler. Sahte adaptörlerle aynı uygulamayı
/// kurmak bu yüzden mümkündür.
@MainActor
@Observable
final class AppContainer {
    let dependencies: LibraryDependencies
    let pipeline: AnalysisPipeline
    private let entitlementProvider: StoreKitEntitlementProvider

    private(set) var isReady = false

    init() throws {
        let container = try ModelContainer(
            for: ShotRecord.self,
            configurations: ModelConfiguration(
                // 07 §4: ekran görüntüsü metni cihaz kilitliyken okunamamalı.
                // Depo, sistemin varsayılan dosya koruma sınıfıyla korunur.
                isStoredInMemoryOnly: false
            )
        )
        let store = ShotStore(modelContainer: container)
        let index = HybridIndex(store: store)

        let source = PhotosShotSource()
        let recognizer = VisionTextRecognizer()
        let entitlements = StoreKitEntitlementProvider()
        let settings = UserDefaultsSettingsStore()

        entitlementProvider = entitlements

        // Analizör seçimi çalışma zamanına bırakılır: kullanıcı zekâ modunu kapatabilir,
        // model arka planda indirilmeyi bitirebilir (bkz. SettingsAwareAnalyzer).
        let analyzer = SettingsAwareAnalyzer(settings: settings)

        pipeline = AnalysisPipeline(
            source: source,
            recognizer: recognizer,
            analyzer: analyzer,
            index: index,
            indexLimit: FreeTierLimits.indexedShotCount
        )

        dependencies = LibraryDependencies(
            index: index,
            pipeline: pipeline,
            analyzer: analyzer,
            source: source,
            actions: EventKitActionPerformer(),
            entitlements: entitlements,
            quota: QuotaLedger(entitlements: entitlements),
            clipboard: SystemClipboard(),
            settings: settings,
            intelligenceStatus: FoundationModelAnalyzer.availabilityDescription()
        )
    }

    /// Uygulama açılışında bir kez çağrılır.
    func start() async {
        // StoreKit dinleyicisi ilk iş: uygulama kapalıyken tamamlanan işlemler
        // (ör. "Ask to Buy" onayı) burada yakalanır.
        await entitlementProvider.start()
        await applyEntitlement()

        // Yetki değişimlerini dinle: Pro olunca indeksleme sınırı kalkar.
        Task { [entitlementProvider, pipeline] in
            for await entitlement in entitlementProvider.updates() {
                await pipeline.updateIndexLimit(
                    entitlement.isPro ? nil : FreeTierLimits.indexedShotCount
                )
            }
        }

        isReady = true
    }

    private func applyEntitlement() async {
        let entitlement = await entitlementProvider.current
        await pipeline.updateIndexLimit(
            entitlement.isPro ? nil : FreeTierLimits.indexedShotCount
        )
    }
}
