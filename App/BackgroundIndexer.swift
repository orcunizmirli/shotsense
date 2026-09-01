import AppFoundation
import BackgroundTasks
import Foundation
import ShotCore

/// Arka plan indeksleme görevi (03 §7).
///
/// `BGProcessingTask` seçilmesinin sebebi: bu iş uzun sürer ve sistemin uygun bulduğu
/// zamanda (cihaz boşta, çoğunlukla şarjdayken ve gece) yapılmalıdır. `BGAppRefreshTask`
/// yalnız saniyeler verir; 5.000 görselin analizi ona sığmaz.
enum BackgroundIndexer {
    static let identifier = "com.shotsense.app.indexing"

    /// Uygulama başlatılırken, `application(_:didFinishLaunching...)` eşdeğerinde çağrılır.
    /// Kayıt gecikirse sistem görevi hiç teslim etmez.
    static func register(pipeline: AnalysisPipeline, settings: any SettingsStoring) {
        // `using: .main` bilinçli: `nil` verilirse sistem işleyiciyi kendi arka plan
        // kuyruğunda çağırır ve `BGTask` Sendable OLMADIĞI için görevi asenkron işe
        // taşımak veri yarışı olur (Swift 6 bunu derlemez). Ana kuyrukta kalınca görev
        // ana aktöre bağlıdır ve tamamlama çağrısı tek bir yerden yapılır. İşleyici
        // ağır iş yapmaz; yalnız asenkron işi başlatıp döner.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier, using: .main
        ) { task in
            MainActor.assumeIsolated {
                guard let processingTask = task as? BGProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                handle(processingTask, pipeline: pipeline, settings: settings)
            }
        }
    }

    static func schedule(settings flags: FeatureFlags) {
        guard flags.backgroundIndexingEnabled else { return }

        let request = BGProcessingTaskRequest(identifier: identifier)
        // KANON §1: bu iş hiçbir zaman ağ istemez.
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = flags.indexOnlyWhileCharging
        // En erken 1 saat sonra: daha agresif planlamak sistemin görevi kısmasına yol açar.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.debug(.lifecycle, "Arka plan indeksleme planlandı")
        } catch {
            Log.warning(.lifecycle, "Arka plan görevi planlanamadı")
        }
    }

    @MainActor
    private static func handle(
        _ task: BGProcessingTask,
        pipeline: AnalysisPipeline,
        settings: any SettingsStoring
    ) {
        // Bir sonraki tur hemen planlanır: sistem görevi sonlandırsa bile zincir kopmaz.
        Task {
            await schedule(settings: settings.flags())
        }

        let work = Task {
            _ = try? await pipeline.synchronizeLibrary()
            // Küçük partiler: sistem görevi her an sonlandırabilir; her parti sonunda
            // yapılan iş kalıcıdır, baştan başlamak gerekmez.
            while await pipeline.processPending(limit: 25) > 0 {
                if Task.isCancelled { break }
            }
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
        }
    }
}
