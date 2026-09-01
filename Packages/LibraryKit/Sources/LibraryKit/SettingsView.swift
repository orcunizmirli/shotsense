import AppFoundation
import DesignSystem
import ShotCore
import SwiftUI

/// Ayarlar ekranı (02 §2.5).
public struct SettingsView: View {
    @State private var flags = FeatureFlags.default
    @State private var entitlement = Entitlement.free
    @State private var counts: IndexCounts?
    @State private var isResetConfirmationPresented = false

    private let dependencies: LibraryDependencies
    private let paywall: PaywallPresenter

    public init(dependencies: LibraryDependencies, paywall: PaywallPresenter) {
        self.dependencies = dependencies
        self.paywall = paywall
    }

    public var body: some View {
        List {
            subscriptionSection
            intelligenceSection
            indexingSection
            privacySection
            dataSection
        }
        .navigationTitle("Ayarlar")
        .task {
            flags = await dependencies.settings.flags()
            entitlement = await dependencies.entitlements.current
            counts = try? await dependencies.index.counts()
        }
        .confirmationDialog(
            "İndeks sıfırlansın mı?",
            isPresented: $isResetConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Sıfırla", role: .destructive) {
                Task {
                    try? await dependencies.index.resetIndex()
                    counts = try? await dependencies.index.counts()
                }
            }
        } message: {
            Text("Analiz sonuçları silinir. Ekran görüntülerinin silinmez.")
        }
    }

    private var subscriptionSection: some View {
        Section("Abonelik") {
            if entitlement.isPro {
                HStack(spacing: Token.Space.md) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("ShotSense Pro").font(Token.Typography.headline)
                        Text("Sınırsız indeksleme ve arama")
                            .font(Token.Typography.micro)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: Token.minimumTapTarget)
            } else {
                Button {
                    paywall.presentManually()
                } label: {
                    HStack(spacing: Token.Space.md) {
                        Image(systemName: "sparkles").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Pro'ya geç").font(Token.Typography.headline)
                            Text("En yeni \(FreeTierLimits.indexedShotCount) yerine tümü, "
                                + "sınırsız akıllı arama")
                                .font(Token.Typography.micro)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.quaternary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .frame(minHeight: Token.minimumTapTarget)
            }
        }
    }

    private var intelligenceSection: some View {
        Section("Zekâ") {
            Toggle("Akıllı analiz", isOn: intelligenceBinding)
                .frame(minHeight: Token.minimumTapTarget)

            if let status = dependencies.intelligenceStatus {
                // "Desteklenmiyor" demek yetmez: kullanıcı Apple Intelligence'ı kendisi
                // açabilir, o yüzden sebep ve çözüm gösterilir (07 §6).
                Label(status, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Özetler ve bilgi çıkarımı cihazındaki Apple Intelligence ile üretiliyor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var indexingSection: some View {
        Section("İndeksleme") {
            Toggle("Arka planda indeksle", isOn: backgroundIndexingBinding)
                .frame(minHeight: Token.minimumTapTarget)
            Toggle("Yalnız şarjdayken", isOn: chargingOnlyBinding)
                .frame(minHeight: Token.minimumTapTarget)

            if let counts {
                LabeledContent("Durum") {
                    Text("\(counts.analyzed) / \(counts.total)")
                        .foregroundStyle(.secondary)
                }
                if counts.failed > 0 {
                    LabeledContent("Başarısız") {
                        Text("\(counts.failed)").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var privacySection: some View {
        Section("Gizlilik") {
            Label(
                "Bu uygulama hiçbir ağ isteği yapmaz. Görsellerin, metinlerin ve analiz "
                    + "sonuçların cihazından çıkmaz.",
                systemImage: "lock.shield"
            )
            .font(.caption)
        }
    }

    private var dataSection: some View {
        Section("Veri") {
            Button("İndeksi sıfırla", role: .destructive) {
                isResetConfirmationPresented = true
            }
            .frame(minHeight: Token.minimumTapTarget)
        }
    }

    // MARK: - Bağlamalar

    private var intelligenceBinding: Binding<Bool> {
        binding(\.intelligenceEnabled) { $0.intelligenceEnabled = $1 }
    }

    private var backgroundIndexingBinding: Binding<Bool> {
        binding(\.backgroundIndexingEnabled) { $0.backgroundIndexingEnabled = $1 }
    }

    private var chargingOnlyBinding: Binding<Bool> {
        binding(\.indexOnlyWhileCharging) { $0.indexOnlyWhileCharging = $1 }
    }

    private func binding(
        _ keyPath: KeyPath<FeatureFlags, Bool>,
        set: @escaping (inout FeatureFlags, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { flags[keyPath: keyPath] },
            set: { newValue in
                var updated = flags
                set(&updated, newValue)
                flags = updated
                Task { await dependencies.settings.update(updated) }
            }
        )
    }
}
