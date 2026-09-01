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
    @State private var didSucceed = false
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
                VStack(spacing: Token.Space.xl) {
                    hero
                    benefits
                    productList
                    legal
                }
                .padding(.horizontal, Token.Space.lg)
                .padding(.bottom, 120) // yüzen satın alma çubuğu için yer
            }
            .scrollIndicators(.hidden)
            .background(backdrop)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(.surface, in: Circle())
                    }
                    .accessibilityLabel("Kapat")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Geri yükle") {
                        Task { try? await dependencies.entitlements.restorePurchases() }
                    }
                    .font(Token.Typography.caption)
                }
            }
            .overlay(alignment: .bottom) { purchaseBar }
            .task { await loadProducts() }
            .alert("Satın alma tamamlanamadı", isPresented: errorBinding) {
                Button("Tamam") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sensoryFeedback(.success, trigger: didSucceed)
        }
    }

    /// Üstten aşağı sönen vurgu rengi. Düz zemin yerine derinlik: abonelik ekranının
    /// "özel bir yer" hissi vermesi dönüşümü ölçülebilir biçimde etkiler.
    private var backdrop: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.16), .clear],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    // MARK: - Başlık

    private var hero: some View {
        VStack(spacing: Token.Space.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.accentColor.gradient)
                .symbolEffect(.pulse)

            Text(Self.headline(for: trigger))
                .font(Token.Typography.display)
                .multilineTextAlignment(.center)

            Text("Her şey cihazında kalmaya devam eder.")
                .font(Token.Typography.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, Token.Space.lg)
    }

    // MARK: - Faydalar

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Token.Space.md) {
            benefit("infinity", "Sınırsız indeksleme", "Kitaplığının tamamı aranabilir olur")
            benefit("sparkle.magnifyingglass", "Sınırsız akıllı arama", "Doğal dilde sor, kota yok")
            benefit("bell.badge", "Sınırsız aksiyon", "Hatırlatıcı ve takvim etkinliği")
            benefit("wand.and.sparkles", "Temizlik asistanı", "Yinelenen ve süresi geçmişleri bul")
        }
        .padding(Token.Space.lg)
        .surfaceCard()
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: Token.Space.md) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Token.Typography.headline)
                Text(detail).font(Token.Typography.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Ürünler

    private var productList: some View {
        VStack(spacing: Token.Space.sm) {
            ForEach(products) { product in
                productCard(product)
            }
        }
    }

    private func productCard(_ product: PurchasableProduct) -> some View {
        let isSelected = selectedProductIdentifier == product.identifier

        return Button {
            withAnimation(Token.Motion.quick) {
                selectedProductIdentifier = product.identifier
            }
        } label: {
            HStack(spacing: Token.Space.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    // Ternary iki dalı aynı tipe zorlar; `.quaternary` bir Color değil
                    // hiyerarşik stildir. Seçilmemiş hâl için sönük bir Color kullanılır.
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName).font(Token.Typography.headline)
                    if product.hasIntroductoryOffer {
                        Text("7 gün ücretsiz dene")
                            .font(Token.Typography.micro)
                            .foregroundStyle(.tint)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(product.displayPrice).font(Token.Typography.headline)
                    if let period = product.periodDescription {
                        Text("/ \(period)")
                            .font(Token.Typography.micro)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Token.Space.lg)
            .background(
                RoundedRectangle(cornerRadius: Token.Radius.lg, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : .surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Token.Radius.lg, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : .hairline,
                        lineWidth: isSelected ? 2 : 0.5
                    )
            }
        }
        .buttonStyle(.pressableCard)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    // MARK: - Satın alma

    private var purchaseBar: some View {
        VStack(spacing: Token.Space.sm) {
            Button {
                Task { await purchase() }
            } label: {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(selectedProductHasTrial ? "Ücretsiz denemeyi başlat" : "Devam et")
                }
            }
            .buttonStyle(.prominentAction)
            .disabled(selectedProductIdentifier == nil || isPurchasing)

            Text("İstediğin zaman iptal edebilirsin.")
                .font(Token.Typography.micro)
                .foregroundStyle(.secondary)
        }
        .padding(Token.Space.lg)
        .background(.thinMaterial)
    }

    private var selectedProductHasTrial: Bool {
        products.first { $0.identifier == selectedProductIdentifier }?.hasIntroductoryOffer ?? false
    }

    private var legal: some View {
        Text("Abonelik, iptal edilmediği sürece dönem sonunda otomatik yenilenir. "
            + "Yönetim ve iptal App Store hesap ayarlarından yapılır.")
            .font(Token.Typography.micro)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    private func loadProducts() async {
        products = await (try? dependencies.entitlements.availableProducts()) ?? []
        // Yıllık varsayılan seçili: kullanıcı karşılaştırmayı yıllık üzerinden yapar (06 §2).
        selectedProductIdentifier = products.first { $0.periodDescription == "yıl" }?.identifier
            ?? products.first?.identifier
    }

    private func purchase() async {
        guard let identifier = selectedProductIdentifier else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let outcome = try await dependencies.entitlements.purchase(productIdentifier: identifier)
            // İptal bir hata değildir; kullanıcıya uyarı göstermek can sıkıcı olur.
            if outcome == .purchased {
                didSucceed = true
                dismiss()
            }
        } catch {
            Log.warning(.paywall, "Satın alma başarısız")
            errorMessage = "Lütfen tekrar dene."
        }
    }

    static func headline(for trigger: PaywallTrigger) -> String {
        switch trigger {
        case .indexLimitReached: return "Tüm ekran görüntülerini aç"
        case .searchQuotaExhausted: return "Bu ay akıllı aramaların doldu"
        case .actionQuotaExhausted: return "Hatırlatıcı hakkın doldu"
        case .proFeatureTapped, .settings: return "ShotSense Pro"
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
