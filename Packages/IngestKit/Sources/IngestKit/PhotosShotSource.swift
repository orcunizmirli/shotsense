import AppFoundation
import Foundation
import Photos
import ShotCore

/// `ShotSourcing` portunun Photos gerçeklemesi.
///
/// Tasarım kararları:
///
/// - **Görsel verisi `Data` olarak alınır** (`requestImageDataAndOrientation`), `UIImage`
///   olarak değil: domain `UIImage` bilmez ve tam çözünürlüklü görseli belleğe açmadan
///   ImageIO ile küçültebiliriz.
/// - **iCloud indirmesi kapalıdır** (`isNetworkAccessAllowed = false`). KANON §1 ağ yok
///   diyor; Photos üzerinden de olsa arka planda veri indirmek bu taahhüdü zedeler. Yalnız
///   iCloud'da duran bir asset analiz edilemez, `pending` kalır ve cihaza indiğinde işlenir.
/// - **Silme yalnız kullanıcı onayıyla** (KANON §8): `performChanges` sistemin kendi onay
///   diyaloğunu gösterir, uygulama sessizce silemez.
///
/// `@unchecked Sendable`: `PHImageManager` ve `PHPhotoLibrary` Photos tarafından thread-safe
/// belgelenmiştir; tipin kendi değiştirilebilir durumu yoktur (değişiklik gözlemcisinin
/// durumu `PhotoLibraryChangeBridge` içinde kilitle korunur).
public final class PhotosShotSource: ShotSourcing, @unchecked Sendable {
    private let imageManager: PHImageManager
    private let changeBridge = PhotoLibraryChangeBridge()

    public init(imageManager: PHImageManager = .default()) {
        self.imageManager = imageManager
    }

    // MARK: - Yetkilendirme

    public var authorizationStatus: ShotLibraryAuthorization {
        get async { Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite)) }
    }

    public func requestAuthorization() async -> ShotLibraryAuthorization {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        Log.info(.ingest, "Fotoğraf izni sonucu", detail: String(describing: status))
        return Self.map(status)
    }

    private static func map(_ status: PHAuthorizationStatus) -> ShotLibraryAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted, .denied: return .denied
        case .limited: return .limited
        case .authorized: return .authorized
        @unknown default: return .denied
        }
    }

    // MARK: - Listeleme

    public func screenshots(newerThan date: Date?) async throws -> [ShotAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let date {
            options.predicate = NSPredicate(format: "creationDate > %@", date as NSDate)
        }

        let result = fetchScreenshots(options: options)
        var assets: [ShotAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(
                ShotAsset(
                    identifier: asset.localIdentifier,
                    createdAt: asset.creationDate ?? Date(timeIntervalSince1970: 0),
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight
                )
            )
        }
        Log.info(.ingest, "Ekran görüntüsü tarandı", detail: "\(assets.count) adet")
        return assets
    }

    /// Önce "Ekran Görüntüleri" akıllı albümü denenir; yoksa medya alt türüne göre süzülür.
    ///
    /// İkinci yol **sınırlı erişimde** (`.limited`) gereklidir: orada akıllı albüm görünmez,
    /// ama kullanıcının seçtiği görseller alt tür süzgeciyle bulunabilir.
    private func fetchScreenshots(options: PHFetchOptions) -> PHFetchResult<PHAsset> {
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil
        )
        if let album = albums.firstObject {
            let result = PHAsset.fetchAssets(in: album, options: options)
            if result.count > 0 { return result }
        }

        let subtypePredicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        let fallbackOptions = PHFetchOptions()
        fallbackOptions.sortDescriptors = options.sortDescriptors
        fallbackOptions.predicate = options.predicate.map {
            NSCompoundPredicate(andPredicateWithSubpredicates: [$0, subtypePredicate])
        } ?? subtypePredicate
        return PHAsset.fetchAssets(with: .image, options: fallbackOptions)
    }

    // MARK: - Görsel verisi

    public func imageData(for identifier: String, maxPixelSize: Int) async throws -> Data {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier], options: nil
        ).firstObject else {
            throw AppError(.notFound, "Asset bulunamadı")
        }

        let original = try await requestImageData(for: asset)
        // Zaten hedeften küçükse yeniden kodlamak kalite kaybından başka bir şey getirmez.
        guard max(asset.pixelWidth, asset.pixelHeight) > maxPixelSize else { return original }
        return try ImageDownscaler.downscaledJPEG(from: original, maxPixelSize: maxPixelSize)
    }

    private func requestImageData(for asset: PHAsset) async throws -> Data {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        // Ağ yok (KANON §1): yalnız iCloud'da duran asset burada hata döner ve pending kalır.
        options.isNetworkAccessAllowed = false

        return try await withCheckedThrowingContinuation { continuation in
            imageManager.requestImageDataAndOrientation(
                for: asset, options: options
            ) { data, _, _, info in
                if let data {
                    continuation.resume(returning: data)
                    return
                }
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                continuation.resume(
                    throwing: isInCloud
                        // Geçici: kullanıcı görseli cihaza indirdiğinde yeniden denenir.
                        ? AppError(.transient, "Görsel yalnız iCloud'da")
                        : AppError(.notFound, "Görsel verisi okunamadı")
                )
            }
        }
    }

    // MARK: - Değişiklikler

    public func changes() -> AsyncStream<ShotLibraryChange> {
        changeBridge.stream()
    }

    // MARK: - Silme

    public func deleteAssets(identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard assets.count > 0 else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            Log.info(.ingest, "Kullanıcı onayıyla silindi", detail: "\(assets.count) adet")
        } catch {
            // Kullanıcı sistem diyaloğunda iptal ettiyse de buraya düşülür; bu bir hata değil.
            throw AppError(.permissionDenied, "Silme onaylanmadı", underlying: error)
        }
    }
}
