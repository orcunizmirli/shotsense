import AppFoundation
import DesignSystem
import ShotCore
import SwiftUI

/// Abonelik ekranı (02 §2.6, 06 §5).
///
/// App Review Guideline 3.1.1 gereği fiyat, periyot, otomatik yenileme bilgisi ve
/// "Satın alımları geri yükle" **her paywall'da** görünür olmalıdır.
public struct PaywallView: View {
    @State private var products: [PurchasableProduct] = []
    @State private var selectedProductIdentifier: String?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let dependencies: LibraryDependencies
    private let trigger: PaywallTrigger

    public init(dependencies: LibraryDependencies, trigger: PaywallTrigger) {
        self.dependencies = dependencies
        self.trigger = trigger
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Token.Space.xl) {
                    headline
                    benefits
                    productList
                    purchaseButton
                    legal
                }
                .padding(Token.Space.lg)
            }
            .navigationTitle("ShotSense Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Geri yükle") {
                        Task { try? await dependencies.entitlements.restorePurchases() }
                    }
                }
            }
            .task {
                products = (try? await dependencies.entitlements.availableProducts()) ?? []
                // Yıllık varsayılan seçili: kullanıcı karşılaştırmayı yıllık üzerinden yapar.
                selectedProductIdentifier = products.first { $0.periodDescription == "yıl" }?
                    .identifier ?? products.first?.identifier
            }
            .alert("Satın alma tamamlanamadı", isPresented: errorBinding) {
                Button("Tamam") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    /// Başlık tetikleyiciye göre değişir: kullanıcı hangi duvara çarptıysa onun cevabı verilir.
    private var headline: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            Text(Self.headline(for: trigger))
                .font(.title2.bold())
            Text("Her şey cihazında kalmaya devam eder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Token.Space.md) {
            benefit("infinity", "Tüm ekran görüntülerin indekslenir")
            benefit("sparkle.magnifyingglass", "Sınırsız akıllı arama")
            benefit("bell.badge", "Sınırsız hatırlatıcı ve takvim etkinliği")
            benefit("folder.badge.gearshape", "Otomatik koleksiyonlar ve temizlik asistanı")
        }
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
    }

    private var productList: some View {
        VStack(spacing: Token.Space.sm) {
            ForEach(products) { product in
                Button {
                    selectedProductIdentifier = product.identifier
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName).font(.headline)
                            if product.hasIntroductoryOffer {
                                Text("7 gün ücretsiz dene").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(product.displayPrice).font(.headline)
                            if let period = product.periodDescription {
                                Text("/ \(period)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(Token.Space.md)
                    .background(
                        RoundedRectangle(cornerRadius: Token.Radius.md)
                            .strokeBorder(
                                selectedProductIdentifier == product.identifier
                                    ? Color.accentColor : Color.gray.opacity(0.3),
                                lineWidth: selectedProductIdentifier == product.identifier ? 2 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    selectedProductIdentifier == product.identifier ? [.isButton, .isSelected] : .isButton
                )
            }
        }
    }

    private var purchaseButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView()
                } else {
                    Text("Devam et")
                }
            }
            .frame(maxWidth: .infinity, minHeight: Token.minimumTapTarget)
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedProductIdentifier == nil || isPurchasing)
    }

    private var legal: some View {
        Text("Abonelik, iptal edilmediği sürece dönem sonunda otomatik yenilenir. "
            + "Yönetim ve iptal App Store hesap ayarlarından yapılır.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func purchase() async {
        guard let identifier = selectedProductIdentifier else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let outcome = try await dependencies.entitlements.purchase(productIdentifier: identifier)
            // İptal bir hata değildir; kullanıcıya uyarı göstermek can sıkıcı olur.
            if outcome == .purchased { dismiss() }
        } catch {
            Log.warning(.paywall, "Satın alma başarısız")
            errorMessage = "Lütfen tekrar dene."
        }
    }

    static func headline(for trigger: PaywallTrigger) -> String {
        switch trigger {
        case .indexLimitReached:
            return "Tüm ekran görüntülerini aç"
        case .searchQuotaExhausted:
            return "Bu ay akıllı aramaların doldu"
        case .actionQuotaExhausted:
            return "Hatırlatıcıya çevirme hakkın doldu"
        case .proFeatureTapped, .settings:
            return "ShotSense Pro"
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
