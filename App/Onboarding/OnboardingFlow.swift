import DesignSystem
import PhotosUI
import ShotCore
import SwiftUI

/// İlk açılış akışı (02 §2.1).
///
/// **Sıralama kanonu (KANON §9):** izin ekranı asla ilk ekran değildir. Kullanıcı önce
/// ürünün kendi ekran görüntüsünde ne yaptığını **görür**, sonra izin istenir. İzin
/// ekranını öne almak, değeri görmeden reddeden kullanıcı üretir ve o karar kalıcıdır.
///
/// `@MainActor`: `body` dışındaki yardımcı görünüm özellikleri (valueStep, sampleStep, …)
/// varsayılan olarak izole DEĞİLDİR; oradan `@MainActor` bir görünüm değiştiricisini
/// (DesignSystem'in `surfaceCard`ı) çağırmak Swift 6'da hata, `@State` okumak uyarıdır.
/// Tip düzeyinde işaretlemek doğru olanı söyler: bu görünümün tamamı ana aktörde yaşar.
@MainActor
struct OnboardingFlow: View {
    enum Step: Int, CaseIterable {
        case value
        case sample
        case permission
        case indexing
    }

    let analyzeSample: @Sendable (Data) async -> ShotAnalysis?
    let requestPhotoAccess: @Sendable () async -> ShotLibraryAuthorization
    let onFinish: () -> Void

    @State private var step: Step = .value
    @State private var selection: PhotosPickerItem?
    @State private var sampleImage: Data?
    @State private var sampleAnalysis: ShotAnalysis?
    @State private var isAnalyzing = false
    @State private var authorization: ShotLibraryAuthorization = .notDetermined

    var body: some View {
        VStack(spacing: Token.Space.xl) {
            ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
                .padding(.horizontal, Token.Space.lg)
                .animation(Token.Motion.standard, value: step)

            Group {
                switch step {
                case .value: valueStep
                case .sample: sampleStep
                case .permission: permissionStep
                case .indexing: indexingStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Adımlar yatay kayarak geçer: kullanıcı akışta nerede olduğunu ve geri
            // dönüşün mümkün olduğunu hareketten anlar.
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(Token.Motion.standard, value: step)

            footer
        }
        .padding(Token.Space.lg)
        .interactiveDismissDisabled()
    }

    // MARK: - 1. Değer

    private var valueStep: some View {
        VStack(spacing: Token.Space.lg) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Ekran görüntülerin aranabilir olsun")
                .font(Token.Typography.display)
                .multilineTextAlignment(.center)
            Text("ShotSense fişleri, biletleri, wifi şifrelerini ve daha fazlasını cihazında "
                + "tanır. Hiçbir görselin telefonundan çıkmaz.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 2. Örnek

    /// **İzin istemeden** çalışır: `PhotosPicker` kullanıcının seçtiği tek görseli verir,
    /// kitaplık erişimi gerektirmez. Değer kanıtı burada üretilir.
    private var sampleStep: some View {
        VStack(spacing: Token.Space.lg) {
            Text("Bir ekran görüntüsü seç, ne yapabildiğimizi gör")
                .font(Token.Typography.title)
                .multilineTextAlignment(.center)

            if let sampleImage {
                DecodedImage(data: sampleImage, maxPixelSize: 900)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .frame(maxHeight: 240)
            }

            if isAnalyzing {
                ProgressView("Analiz ediliyor…")
            } else if let sampleAnalysis {
                VStack(alignment: .leading, spacing: Token.Space.sm) {
                    CategoryBadge(category: sampleAnalysis.category)
                    Text(sampleAnalysis.title.isEmpty ? "Başlıksız" : sampleAnalysis.title)
                        .font(.headline)
                    if !sampleAnalysis.summary.isEmpty {
                        Text(sampleAnalysis.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sampleAnalysis.displayableEntities.prefix(3)) { entity in
                        Label(entity.rawValue, systemImage: "checkmark.circle")
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Token.Space.md)
                .background(.surface, in: RoundedRectangle(cornerRadius: Token.Radius.md))
            }

            PhotosPicker(selection: $selection, matching: .screenshots) {
                Label(
                    sampleImage == nil ? "Ekran görüntüsü seç" : "Başka bir tane dene",
                    systemImage: "photo"
                )
                .font(Token.Typography.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .surfaceCard(radius: Token.Radius.md)
            }
            .buttonStyle(.pressable)
        }
        .task(id: selection) {
            await loadSample()
        }
    }

    private func loadSample() async {
        guard let selection else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        guard let data = try? await selection.loadTransferable(type: Data.self) else { return }
        sampleImage = data
        sampleAnalysis = await analyzeSample(data)
    }

    // MARK: - 3. İzin

    private var permissionStep: some View {
        VStack(spacing: Token.Space.lg) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Tüm ekran görüntülerini indeksleyelim mi?")
                .font(Token.Typography.title)
                .multilineTextAlignment(.center)
            Text("Erişim izni verirsen kitaplığının tamamı aranabilir olur. Analiz cihazında "
                + "yapılır; hiçbir veri gönderilmez.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if authorization == .denied {
                // Reddeden kullanıcı çıkmaza girmemeli: sınırlı mod da çalışır (07 §2).
                Text("İzin vermedin. Uygulamayı kullanmaya devam edebilirsin; ekran "
                    + "görüntülerini elle ekleyerek aratabilirsin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - 4. İndeksleme

    private var indexingStep: some View {
        VStack(spacing: Token.Space.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Hazırsın")
                .font(Token.Typography.display)
            Text("İndeksleme arka planda sürecek. Kitaplık dolmaya başlayacak; beklemene "
                + "gerek yok.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Alt bar

    private var footer: some View {
        HStack {
            if step != .value {
                Button("Geri") { back() }
                    .frame(minHeight: Token.minimumTapTarget)
            }
            Spacer()
            Button(primaryTitle) {
                Task { await advance() }
            }
            .buttonStyle(.prominentAction)
            .frame(maxWidth: step == .value ? .infinity : 220)
        }
    }

    private var primaryTitle: String {
        switch step {
        case .value: return "Başla"
        case .sample: return sampleAnalysis == nil ? "Atla" : "Devam"
        case .permission: return authorization == .denied ? "Devam" : "İzin ver"
        case .indexing: return "Bitir"
        }
    }

    private func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func advance() async {
        switch step {
        case .value:
            step = .sample
        case .sample:
            step = .permission
        case .permission:
            if authorization == .notDetermined {
                authorization = await requestPhotoAccess()
                // Reddedildiyse kullanıcıyı burada tutmayız; sınırlı modda devam eder.
                if authorization == .denied { return }
            }
            step = .indexing
        case .indexing:
            onFinish()
        }
    }
}
