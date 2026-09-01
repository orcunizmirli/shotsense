import AppFoundation
import IntelligenceKit
import LibraryKit
import OCRKit
import ShotCore
import SwiftUI

/// Uygulamanın giriş noktası.
@main
struct ShotSenseApp: App {
    @State private var container: AppContainer?
    @State private var startupError: String?
    @AppStorage("onboarding.completed") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            content
                .task { await start() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let container {
            RootView(dependencies: container.dependencies)
                // `.constant` binding kullanılmaz: SwiftUI örtüyü kapatmak istediğinde
                // (sistem tetiklemesi, erişilebilirlik kapatması) bağlamaya yazar ve
                // sabit bir bağlama bu yazmayı sessizce yutar — örtü açık kalır.
                .fullScreenCover(isPresented: onboardingBinding) {
                    OnboardingFlow(
                        analyzeSample: Self.sampleAnalyzer(),
                        requestPhotoAccess: { await container.dependencies.source.requestAuthorization() },
                        onFinish: { hasCompletedOnboarding = true }
                    )
                }
        } else if let startupError {
            // Veri deposu açılamazsa uygulama boş ekranla açılmaz; ne olduğu söylenir.
            ContentUnavailableView(
                "Başlatılamadı",
                systemImage: "exclamationmark.triangle",
                description: Text(startupError)
            )
        } else {
            ProgressView()
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding },
            set: { isPresented in
                if !isPresented { hasCompletedOnboarding = true }
            }
        )
    }

    private func start() async {
        guard container == nil else { return }
        do {
            let container = try AppContainer()
            await container.start()
            BackgroundIndexer.register(
                pipeline: container.pipeline, settings: container.dependencies.settings
            )
            await BackgroundIndexer.schedule(settings: container.dependencies.settings.flags())
            self.container = container
        } catch {
            Log.error(.lifecycle, "AppContainer kurulamadı", error: error)
            startupError = "Veri deposu açılamadı. Uygulamayı yeniden başlatmayı dene."
        }
    }

    /// Onboarding'in örnek analizi: kitaplık izni **olmadan** çalışır, kullanıcının
    /// `PhotosPicker` ile seçtiği tek görsel üzerinde (02 §2.1).
    private static func sampleAnalyzer() -> @Sendable (Data) async -> ShotAnalysis? {
        { data in
            let recognizer = VisionTextRecognizer()
            let analyzer = await AnalyzerFactory.make()
            guard let document = try? await recognizer.recognize(imageData: data, languages: []),
                  let analysis = try? await analyzer.analyze(document)
            else { return nil }
            return analysis
        }
    }
}
