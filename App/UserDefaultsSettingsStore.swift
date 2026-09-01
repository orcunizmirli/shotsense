import AppFoundation
import Foundation
import ShotCore

/// `SettingsStoring` portunun `UserDefaults` gerçeklemesi.
///
/// Yalnızca **tercih** saklar — ekran görüntüsü içeriği asla (07 §4: `UserDefaults`
/// yedeklemeye girer, hassas veri oraya yazılmaz).
actor UserDefaultsSettingsStore: SettingsStoring {
    private let defaults: UserDefaults

    private enum Key {
        static let intelligence = "settings.intelligenceEnabled"
        static let backgroundIndexing = "settings.backgroundIndexingEnabled"
        static let chargingOnly = "settings.indexOnlyWhileCharging"
        static let cleanup = "settings.cleanupAssistantEnabled"
    }

    /// Depo aktörün içinde kurulur: `UserDefaults` `Sendable` değildir ve bir örneği
    /// aktör sınırından geçirmek Swift 6'da veri yarışı riski sayılır.
    init(suiteName: String? = nil) {
        let defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.defaults = defaults
        // Varsayılanlar kayıt edilir ki "hiç ayarlanmamış" ile "kapatılmış" karışmasın:
        // `bool(forKey:)` her ikisinde de false döner.
        defaults.register(defaults: [
            Key.intelligence: true,
            Key.backgroundIndexing: true,
            Key.chargingOnly: false,
            Key.cleanup: false
        ])
    }

    func flags() async -> FeatureFlags {
        FeatureFlags(
            intelligenceEnabled: defaults.bool(forKey: Key.intelligence),
            backgroundIndexingEnabled: defaults.bool(forKey: Key.backgroundIndexing),
            indexOnlyWhileCharging: defaults.bool(forKey: Key.chargingOnly),
            cleanupAssistantEnabled: defaults.bool(forKey: Key.cleanup)
        )
    }

    func update(_ flags: FeatureFlags) async {
        defaults.set(flags.intelligenceEnabled, forKey: Key.intelligence)
        defaults.set(flags.backgroundIndexingEnabled, forKey: Key.backgroundIndexing)
        defaults.set(flags.indexOnlyWhileCharging, forKey: Key.chargingOnly)
        defaults.set(flags.cleanupAssistantEnabled, forKey: Key.cleanup)
    }
}
