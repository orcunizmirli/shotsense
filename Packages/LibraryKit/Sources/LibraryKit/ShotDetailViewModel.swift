import AppFoundation
import CoreGraphics
import DesignSystem
import Foundation
import ShotCore

/// Detay ekranının durumu ve aksiyonları.
@MainActor
@Observable
public final class ShotDetailViewModel {
    public private(set) var shot: Shot
    /// Önce önizleme, sonra tam görsel gösterilir: kullanıcı ekran açılır açılmaz bir şey
    /// görür ve tam görsel geldiğinde yerine geçer (aşamalı yükleme).
    public private(set) var previewImage: CGImage?
    public private(set) var heroImage: CGImage?
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

    /// Gösterilecek görsel: tam görsel hazırsa o, değilse önizleme.
    public var displayImage: CGImage? { heroImage ?? previewImage }

    public func load() async {
        if let data = try? await dependencies.index.thumbnail(for: shot.assetIdentifier) {
            previewImage = await ImageDecoding.decodeInBackground(data, maxPixelSize: 400)
        }
        guard let full = try? await dependencies.source.imageData(
            for: shot.assetIdentifier, maxPixelSize: Self.heroPixelSize
        ) else { return }
        heroImage = await ImageDecoding.decodeInBackground(full, maxPixelSize: Self.heroPixelSize)
    }

    /// Detay ve tam ekran inceleyici için çözünürlük.
    ///
    /// Yakınlaştırma yapıldığı için önizleme boyutu yetmez; tam çözünürlük ise 14 MB'lık
    /// bitmap demektir. 2000 px, 6x yakınlaştırmada bile küçük punto metni okunur kılar.
    static let heroPixelSize = 2000

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

    /// Satır içi geri bildirim ("Kopyalandı").
    public func showToast(_ message: String) {
        toast = message
    }

    /// Varlık türüne göre açılacak sistem bağlantısı.
    ///
    /// Bağlantı açmak arayüz katmanının işidir (`openURL`), bu yüzden model yalnız
    /// **hangi** adresin açılacağını söyler; açma işini görünüm yapar.
    public func actionURL(for entity: ExtractedEntity) -> URL? {
        switch entity.kind {
        case .url:
            return URL(string: entity.normalizedValue)
        case .phone:
            return URL(string: "tel://" + entity.normalizedValue.filter { $0.isNumber || $0 == "+" })
        case .email:
            return URL(string: "mailto:" + entity.normalizedValue)
        case .address:
            let query = entity.rawValue
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "http://maps.apple.com/?q=" + query)
        case .trackingNumber, .flightNumber, .date, .amount, .merchant, .iban,
             .wifiSSID, .wifiPassword, .code, .person:
            return nil
        }
    }

    /// Bağlantısı olmayan aksiyona çevrilebilir türler (tarih) için işlem.
    public func performAction(for entity: ExtractedEntity) async {
        switch entity.kind {
        case .date:
            await createReminder()
        case .trackingNumber, .flightNumber:
            // Takip/uçuş numarası için doğrulanmış bir derin bağlantı yok; kullanıcının
            // kendi uygulamasına yapıştırabilmesi en güvenilir yol.
            showToast("Kopyalayıp takip uygulamanda kullanabilirsin")
        case .url, .phone, .email, .address, .amount, .merchant, .iban,
             .wifiSSID, .wifiPassword, .code, .person:
            break
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
