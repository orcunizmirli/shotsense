import AppFoundation
import Foundation
import ShotCore

/// Detay ekranının durumu ve aksiyonları.
@MainActor
@Observable
public final class ShotDetailViewModel {
    public private(set) var shot: Shot
    public private(set) var thumbnailData: Data?
    public private(set) var fullImageData: Data?
    /// Kullanıcıya gösterilecek geçici geri bildirim ("Hatırlatıcı oluşturuldu").
    public private(set) var toast: String?
    public private(set) var errorMessage: String?

    private let dependencies: LibraryDependencies
    private let paywall: PaywallPresenter

    public init(shot: Shot, dependencies: LibraryDependencies, paywall: PaywallPresenter) {
        self.shot = shot
        self.dependencies = dependencies
        self.paywall = paywall
    }

    /// Yalnız doğrulanmış varlıklar gösterilir (KANON §6).
    public var entities: [ExtractedEntity] {
        shot.analysis.displayableEntities
    }

    /// Aksiyona çevrilebilecek ilk tarih — "Hatırlatıcı kur" düğmesi buna bakar.
    public var actionableDate: Date? {
        entities.compactMap(\.dateValue).min()
    }

    public func load() async {
        thumbnailData = try? await dependencies.index.thumbnail(for: shot.assetIdentifier)
        fullImageData = try? await dependencies.source.imageData(
            for: shot.assetIdentifier, maxPixelSize: 1600
        )
    }

    // MARK: - Aksiyonlar

    public func createReminder() async {
        guard await consumeActionQuota() else { return }
        do {
            try await dependencies.actions.createReminder(
                ReminderDraft(
                    title: shot.analysis.title.isEmpty ? "Ekran görüntüsü" : shot.analysis.title,
                    notes: shot.analysis.summary,
                    dueDate: actionableDate
                )
            )
            toast = "Hatırlatıcı oluşturuldu"
        } catch {
            report(error, fallback: "Hatırlatıcı oluşturulamadı")
        }
    }

    public func createCalendarEvent() async {
        guard let date = actionableDate else {
            errorMessage = "Bu ekran görüntüsünde tarih bulunamadı."
            return
        }
        guard await consumeActionQuota() else { return }
        do {
            try await dependencies.actions.createCalendarEvent(
                CalendarEventDraft(
                    title: shot.analysis.title.isEmpty ? "Etkinlik" : shot.analysis.title,
                    notes: shot.analysis.summary,
                    startDate: date
                )
            )
            toast = "Takvime eklendi"
        } catch {
            report(error, fallback: "Takvime eklenemedi")
        }
    }

    /// Kayıt uygulamadan kaldırılır; **Photos'taki görsel durur** (05 §6).
    public func removeFromLibrary() async {
        do {
            try await dependencies.index.remove(assetIdentifiers: [shot.assetIdentifier])
            toast = "Kitaplıktan kaldırıldı"
        } catch {
            report(error, fallback: "Kaldırılamadı")
        }
    }

    /// Kullanıcı kategoriyi elle düzeltir; kayıt `userCorrected` işaretlenir ve yeniden
    /// analizde bu tercih korunur (01 B9).
    public func correctCategory(to category: ShotCategory) async {
        let corrected = Shot(
            assetIdentifier: shot.assetIdentifier,
            createdAt: shot.createdAt,
            indexedAt: shot.indexedAt,
            status: shot.status,
            schemaVersion: shot.schemaVersion,
            recognizedText: shot.recognizedText,
            ocrLanguages: shot.ocrLanguages,
            barcodePayloads: shot.barcodePayloads,
            analysis: ShotAnalysis(
                category: category,
                categoryConfidence: 1,
                title: shot.analysis.title,
                summary: shot.analysis.summary,
                tags: shot.analysis.tags,
                entities: shot.analysis.entities,
                analyzerKind: shot.analysis.analyzerKind
            ),
            userCorrected: true
        )
        do {
            try await dependencies.index.upsert(corrected)
            shot = corrected
            toast = "Kategori güncellendi"
        } catch {
            report(error, fallback: "Güncellenemedi")
        }
    }

    public func clearToast() {
        toast = nil
        errorMessage = nil
    }

    // MARK: - Yardımcı

    private func consumeActionQuota() async -> Bool {
        guard await dependencies.quota.consume(.action) else {
            paywall.presentAutomatically(.actionQuotaExhausted)
            return false
        }
        return true
    }

    private func report(_ error: any Error, fallback: String) {
        Log.warning(.action, "Aksiyon başarısız")
        // İzin reddi kullanıcıya özel açıklama gerektirir: "hata" demek yerine ne yapacağını söyle.
        if let appError = error as? AppError, appError.kind == .permissionDenied {
            errorMessage = "İzin verilmedi. Ayarlar'dan izin verebilirsin."
        } else {
            errorMessage = fallback
        }
    }
}
