import AppFoundation
import Foundation
import ShotCore
import StoreKit

/// `EntitlementProviding` portunun StoreKit 2 gerçeklemesi (06 §4).
///
/// **Sunucu doğrulaması yok** — çünkü sunucu yok. StoreKit 2 imza doğrulamasını cihazda
/// yapar (`VerificationResult`), bu da makbuz doğrulama uç noktası olmadan güvenilir bir
/// yetki kararı vermeye yeter.
///
/// `Transaction.updates` uygulama yaşam döngüsü boyunca dinlenir: dinlenmezse uygulama
/// kapalıyken tamamlanan (ör. "Ask to Buy" onayı) işlemler kaçırılır ve kullanıcı parasını
/// ödediği hâlde Pro olamaz.
public actor StoreKitEntitlementProvider: EntitlementProviding {
    private var cached: Entitlement = .free
    private var continuations: [UUID: AsyncStream<Entitlement>.Continuation] = [:]
    private var updatesTask: Task<Void, Never>?

    public init() {}

    /// Uygulama açılışında bir kez çağrılır (kompozisyon kökünden).
    ///
    /// Dinleme görevi bilinçli olarak hiç iptal edilmez: sağlayıcı uygulamanın ömrü
    /// boyunca yaşar ve dinlemeyi erken bırakmak, arka planda tamamlanan bir işlemi
    /// kaçırmak demektir.
    public func start() async {
        await refresh()
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    public var current: Entitlement { cached }

    nonisolated public func updates() -> AsyncStream<Entitlement> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(continuation, id: id) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id) }
            }
        }
    }

    private func register(_ continuation: AsyncStream<Entitlement>.Continuation, id: UUID) {
        continuations[id] = continuation
        continuation.yield(cached)
    }

    private func unregister(_ id: UUID) {
        continuations[id] = nil
    }

    // MARK: - Ürünler

    public func availableProducts() async throws -> [PurchasableProduct] {
        do {
            let products = try await Product.products(for: ProductCatalog.allIdentifiers)
            // Katalogdaki sıra korunur: yıllık önce gösterilir (06 §2).
            return ProductCatalog.allIdentifiers.compactMap { identifier in
                products.first { $0.id == identifier }.map(Self.presentable)
            }
        } catch {
            throw AppError(.transient, "Ürünler yüklenemedi", underlying: error)
        }
    }

    private static func presentable(_ product: Product) -> PurchasableProduct {
        PurchasableProduct(
            identifier: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            periodDescription: product.subscription.map { periodDescription($0.subscriptionPeriod) },
            hasIntroductoryOffer: product.subscription?.introductoryOffer != nil
        )
    }

    private static func periodDescription(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day: return period.value == 1 ? "gün" : "\(period.value) gün"
        case .week: return period.value == 1 ? "hafta" : "\(period.value) hafta"
        case .month: return period.value == 1 ? "ay" : "\(period.value) ay"
        case .year: return period.value == 1 ? "yıl" : "\(period.value) yıl"
        @unknown default: return ""
        }
    }

    // MARK: - Satın alma

    public func purchase(productIdentifier: String) async throws -> PurchaseOutcome {
        guard let product = try await Product.products(for: [productIdentifier]).first else {
            throw AppError(.notFound, "Ürün bulunamadı")
        }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw AppError(.transient, "Satın alma tamamlanamadı", underlying: error)
        }

        switch result {
        case let .success(verification):
            await handle(verification)
            return .purchased
        case .pending:
            // "Ask to Buy" veya SCA onayı bekleniyor; işlem sonra Transaction.updates'ten gelir.
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    public func restorePurchases() async throws {
        do {
            try await AppStore.sync()
            await refresh()
        } catch {
            throw AppError(.transient, "Geri yükleme başarısız", underlying: error)
        }
    }

    // MARK: - Yetki hesabı

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result else {
            // Doğrulanamayan işlem yok sayılır; jailbreak/enjeksiyon senaryosunda
            // yetki vermemek doğru davranıştır.
            Log.warning(.paywall, "Doğrulanamayan işlem yok sayıldı")
            return
        }
        // finish() çağrılmazsa işlem her açılışta yeniden teslim edilir.
        await transaction.finish()
        await refresh()
    }

    /// Geçerli yetkileri baştan hesaplar.
    ///
    /// `Transaction.currentEntitlements` ödeme yeniden deneme ve grace period'daki
    /// abonelikleri de içerir; bu yüzden "süresi geçmiş ama hâlâ yetkili" durumu
    /// doğrudan grace period göstergesi olarak kullanılabilir (06 §4).
    public func refresh() async {
        var isPro = false
        var latestExpiry: Date?

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  ProductCatalog.proIdentifiers.contains(transaction.productID),
                  transaction.revocationDate == nil
            else { continue }

            isPro = true
            if let expiration = transaction.expirationDate {
                latestExpiry = max(latestExpiry ?? expiration, expiration)
            }
        }

        let isInGracePeriod = isPro && (latestExpiry.map { $0 < Date() } ?? false)
        let entitlement = Entitlement(
            tier: isPro ? .pro : .free,
            expiresAt: latestExpiry,
            isInGracePeriod: isInGracePeriod
        )

        guard entitlement != cached else { return }
        cached = entitlement
        Log.info(.paywall, "Yetki güncellendi", detail: entitlement.tier.rawValue)
        for continuation in continuations.values {
            continuation.yield(entitlement)
        }
    }
}
