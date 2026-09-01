import AppFoundation
import Foundation
import ShotCore
import ShotCoreTestSupport
@testable import LibraryKit

/// Testlerin ortak kurulumu: tüm portlar sahte, gerçek çerçeve yok.
enum TestDependencies {
    static let epoch = Date(timeIntervalSince1970: 1_767_225_600)

    static func shot(
        identifier: String = "asset-0",
        category: ShotCategory = .receipt,
        createdAt: Date = epoch,
        status: AnalysisStatus = .analyzed,
        title: String = "Market fişi",
        text: String = "TOPLAM 249,90 TL",
        entities: [ExtractedEntity] = []
    ) -> Shot {
        Shot(
            assetIdentifier: identifier,
            createdAt: createdAt,
            indexedAt: createdAt,
            status: status,
            recognizedText: text,
            analysis: ShotAnalysis(
                category: category,
                categoryConfidence: 0.9,
                title: title,
                summary: "özet",
                tags: [],
                entities: entities,
                analyzerKind: .heuristic
            )
        )
    }

    static func make(
        index: FakeIndex,
        source: FakeShotSource = FakeShotSource(),
        analyzer: FakeAnalyzer = FakeAnalyzer(),
        actions: FakeActionPerformer = FakeActionPerformer(),
        entitlements: FakeEntitlementProvider = FakeEntitlementProvider(),
        quota: FakeQuotaMeter = FakeQuotaMeter(),
        clipboard: FakeClipboard = FakeClipboard(),
        settings: FakeSettingsStore = FakeSettingsStore()
    ) -> LibraryDependencies {
        LibraryDependencies(
            index: index,
            pipeline: AnalysisPipeline(
                source: source,
                recognizer: FakeTextRecognizer(),
                analyzer: analyzer,
                index: index,
                dateProvider: MutableDateProvider(now: epoch),
                indexLimit: nil
            ),
            analyzer: analyzer,
            source: source,
            actions: actions,
            entitlements: entitlements,
            quota: quota,
            clipboard: clipboard,
            settings: settings,
            intelligenceStatus: nil
        )
    }
}
