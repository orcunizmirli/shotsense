import AppFoundation
import Foundation
import Photos
import ShotCore

/// `PHPhotoLibraryChangeObserver` delegate geri çağrısını `AsyncStream`'e köprüler.
///
/// Photos değişiklik bildirimini yalnızca **bir kez** ve delegate biçiminde verir; pipeline
/// ise akış bekler. Ayrıca gözlemcinin `NSObject` olması ve geri çağrının rastgele bir
/// kuyrukta gelmesi gerekir — bu yüzden köprü ayrı bir tipte, kilitle korunmuş durumla tutulur.
final class PhotoLibraryChangeBridge: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<ShotLibraryChange>.Continuation] = [:]
    private var fetchResult: PHFetchResult<PHAsset>?
    private var isObserving = false

    func stream() -> AsyncStream<ShotLibraryChange> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            startObservingIfNeeded()
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.lock()
                continuations[id] = nil
                lock.unlock()
            }
        }
    }

    /// `lock` tutulurken çağrılır.
    private func startObservingIfNeeded() {
        guard !isObserving else { return }
        isObserving = true

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        PHPhotoLibrary.shared().register(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        lock.lock()
        defer { lock.unlock() }

        guard let current = fetchResult,
              let details = changeInstance.changeDetails(for: current)
        else { return }

        fetchResult = details.fetchResultAfterChanges

        let inserted = details.insertedObjects.map { asset in
            ShotAsset(
                identifier: asset.localIdentifier,
                createdAt: asset.creationDate ?? Date(timeIntervalSince1970: 0),
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight
            )
        }
        let removed = details.removedObjects.map(\.localIdentifier)
        guard !inserted.isEmpty || !removed.isEmpty else { return }

        let change = ShotLibraryChange(inserted: inserted, removedIdentifiers: removed)
        Log.debug(
            .ingest,
            "Kitaplık değişti",
            detail: "+\(inserted.count) -\(removed.count)"
        )
        for continuation in continuations.values {
            continuation.yield(change)
        }
    }
}
