import AppFoundation
import Foundation
import Observation
import ShotCore

/// Arayüzün ihtiyaç duyduğu portların paketi.
///
/// Yalnız `ShotCore` protokolleri içerir — hangi adaptörün bağlandığını (Vision mı sahte mi,
/// StoreKit mi bellek-içi mi) arayüz **bilmez** (R3). Bu, tüm ekranların gerçek Photos veya
/// StoreKit olmadan test edilebilmesini sağlar.
public struct LibraryDependencies: Sendable {
    public let index: any ShotIndexing
    public let pipeline: AnalysisPipeline
    public let analyzer: any ShotAnalyzing
    public let source: any ShotSourcing
    public let actions: any ActionPerforming
    public let entitlements: any EntitlementProviding
    public let quota: any QuotaMetering
    public let clipboard: any ClipboardWriting
    public let settings: any SettingsStoring
    /// Apple Intelligence kullanılamıyorsa sebebini anlatan metin; kullanılabiliyorsa nil.
    ///
    /// Metni `IntelligenceKit` üretir ama arayüz o paketi göremez (R3), bu yüzden
    /// kompozisyon kökü hazır dizeyi buraya koyar.
    public let intelligenceStatus: String?

    public init(
        index: any ShotIndexing,
        pipeline: AnalysisPipeline,
        analyzer: any ShotAnalyzing,
        source: any ShotSourcing,
        actions: any ActionPerforming,
        entitlements: any EntitlementProviding,
        quota: any QuotaMetering,
        clipboard: any ClipboardWriting,
        settings: any SettingsStoring,
        intelligenceStatus: String?
    ) {
        self.index = index
        self.pipeline = pipeline
        self.analyzer = analyzer
        self.source = source
        self.actions = actions
        self.entitlements = entitlements
        self.quota = quota
        self.clipboard = clipboard
        self.settings = settings
        self.intelligenceStatus = intelligenceStatus
    }
}

/// Paywall'un hangi tetikleyiciyle açıldığını taşıyan, uygulama genelinde paylaşılan durum.
@MainActor
@Observable
public final class PaywallPresenter {
    public private(set) var trigger: PaywallTrigger?
    public var isPresented: Bool {
        get { trigger != nil }
        set { if !newValue { trigger = nil } }
    }

    private let dateProvider: any DateProviding
    private var automaticPresentationDates: [Date] = []

    public init(dateProvider: any DateProviding = SystemDateProvider()) {
        self.dateProvider = dateProvider
    }

    /// Kullanıcının kendi açtığı paywall — kapak uygulanmaz (06 §5).
    public func presentManually() {
        trigger = .settings
    }

    /// Otomatik paywall. Ayda en fazla 3 kez ve kapatıldıktan sonra ≥48 saat (KANON §11).
    ///
    /// - Returns: gösterilip gösterilmediği. `false` dönerse çağıran sessizce devam eder.
    @discardableResult
    public func presentAutomatically(_ trigger: PaywallTrigger) -> Bool {
        let now = dateProvider.now
        automaticPresentationDates.removeAll { now.timeIntervalSince($0) > 30 * 86400 }

        guard automaticPresentationDates.count < 3 else { return false }
        if let last = automaticPresentationDates.last,
           now.timeIntervalSince(last) < 48 * 3600 {
            return false
        }

        automaticPresentationDates.append(now)
        self.trigger = trigger
        return true
    }
}
