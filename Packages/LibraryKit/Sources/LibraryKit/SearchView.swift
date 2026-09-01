import DesignSystem
import ShotCore
import SwiftUI

/// Arama ekranı (02 §2.3).
public struct SearchView: View {
    @State private var model: SearchViewModel

    private let dependencies: LibraryDependencies
    private let paywall: PaywallPresenter

    public init(dependencies: LibraryDependencies, paywall: PaywallPresenter) {
        self.dependencies = dependencies
        self.paywall = paywall
        _model = State(
            wrappedValue: SearchViewModel(dependencies: dependencies, paywall: paywall)
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            filterChips
            content
        }
        .navigationTitle("Ara")
        .searchable(
            text: $model.queryText,
            prompt: "Doğal dilde sor: \"geçen ay 500 TL üstü fişler\""
        )
        .onSubmit(of: .search) {
            Task { await model.submit() }
        }
    }

    /// Modelin sorgudan **ne anladığı** görünür olmalı: sessizce uygulanan filtre,
    /// kullanıcının anlamadığı boş sonuç demektir (02 §2.3).
    @ViewBuilder
    private var filterChips: some View {
        if let intent = model.appliedIntent, intent.hasFilters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Token.Space.sm) {
                    if let category = intent.category {
                        removableChip(
                            title: "kategori: \(CategoryStyle.style(for: category).title)"
                        ) {
                            Task { await model.removeCategoryFilter() }
                        }
                    }
                    if let range = intent.dateRange {
                        removableChip(title: "tarih: \(Self.title(for: range))") {
                            Task { await model.removeDateFilter() }
                        }
                    }
                    if intent.minAmount != nil || intent.maxAmount != nil {
                        removableChip(title: amountChipTitle(intent)) {
                            Task { await model.removeAmountFilter() }
                        }
                    }
                }
                .padding(.horizontal, Token.Space.lg)
                .padding(.vertical, Token.Space.sm)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            StateView(
                symbolName: "magnifyingglass",
                title: "Ne arıyorsun?",
                message: "\"otel wifi şifresi\", \"geçen ay kulaklık fişi\" gibi yazabilirsin."
            )
        case .searching:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noResults:
            StateView(
                symbolName: "questionmark.folder",
                title: "Sonuç yok",
                message: "Filtreleri kaldırmayı veya farklı kelimeler denemeyi dene."
            )
        case .quotaExceeded:
            StateView(
                symbolName: "sparkles",
                title: "Akıllı arama hakkın doldu",
                message: "Bu ay ücretsiz akıllı aramalarını kullandın. Anahtar kelime araması "
                    + "sınırsız çalışmaya devam ediyor.",
                actionTitle: "Pro'ya geç"
            ) {
                paywall.presentManually()
            }
        case let .results(results):
            List(results) { result in
                NavigationLink {
                    ShotDetailView(
                        shot: result.shot, dependencies: dependencies, paywall: paywall
                    )
                } label: {
                    resultRow(result)
                }
            }
            .listStyle(.plain)
        }
    }

    private func resultRow(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.xs) {
            HStack(spacing: Token.Space.sm) {
                CategoryBadge(category: result.shot.analysis.category)
                Text(result.shot.createdAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(result.shot.analysis.title.isEmpty ? "Başlıksız" : result.shot.analysis.title)
                .font(.headline)
            if !result.snippet.isEmpty {
                Text(result.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, Token.Space.xs)
    }

    private func removableChip(title: String, onRemove: @escaping () -> Void) -> some View {
        Button(action: onRemove) {
            HStack(spacing: Token.Space.xs) {
                Text(title).font(.caption)
                Image(systemName: "xmark.circle.fill").imageScale(.small)
            }
            .padding(.horizontal, Token.Space.md)
            .padding(.vertical, Token.Space.sm)
            .background(.surfaceStrong, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: Token.minimumTapTarget)
        .accessibilityLabel("\(title) filtresini kaldır")
    }

    private func amountChipTitle(_ intent: SearchIntent) -> String {
        if let minimum = intent.minAmount { return "tutar: \(Int(minimum))+" }
        if let maximum = intent.maxAmount { return "tutar: \(Int(maximum))-" }
        return "tutar"
    }

    static func title(for range: RelativeDateRange) -> String {
        switch range {
        case .last7Days: return "son 7 gün"
        case .last30Days: return "son 30 gün"
        case .last90Days: return "son 3 ay"
        case .thisYear: return "bu yıl"
        case .lastYear: return "geçen yıl"
        }
    }
}
