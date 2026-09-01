import DesignSystem
import ShotCore
import SwiftUI

/// Arama ekranı (02 §2.3).
public struct SearchView: View {
    @State private var model: SearchViewModel
    @Namespace private var transitionNamespace

    private let dependencies: LibraryDependencies
    private let paywall: PaywallPresenter

    /// Boşta gösterilen başlangıç önerileri.
    ///
    /// Boş bir arama kutusu kullanıcıya ne yazabileceğini söylemez; doğal dil aramasının
    /// varlığı ancak örnekle anlaşılır.
    private static let starterSuggestions = [
        "wifi şifresi",
        "geçen ay fişler",
        "yaklaşan biletler",
        "kargo takip",
        "IBAN"
    ]

    public init(dependencies: LibraryDependencies, paywall: PaywallPresenter) {
        self.dependencies = dependencies
        self.paywall = paywall
        _model = State(
            wrappedValue: SearchViewModel(dependencies: dependencies, paywall: paywall)
        )
    }

    public var body: some View {
        content
            .navigationTitle("Ara")
            .navigationDestination(for: SearchResult.self) { result in
                ShotDetailView(shot: result.shot, dependencies: dependencies, paywall: paywall)
                    .zoomTransition(
                        sourceID: result.shot.assetIdentifier, in: transitionNamespace
                    )
            }
            .alwaysVisibleSearchBar(text: $model.queryText, prompt: "Doğal dilde sor")
            .onSubmit(of: .search) {
                Task { await model.submit() }
            }
            .safeAreaInset(edge: .top, spacing: 0) { SearchFilterBar(model: model) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            suggestions

        case .searching:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .noResults:
            StateView(
                symbolName: "text.page.badge.magnifyingglass",
                title: "Sonuç yok",
                message: model.appliedIntent?.hasFilters == true
                    ? "Filtreleri kaldırmayı dene — yukarıdaki çiplere dokunarak."
                    : "Farklı kelimeler deneyebilirsin."
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
            resultList(results)
        }
    }

    // MARK: - Öneriler

    private var suggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Token.Space.xl) {
                suggestionSection(
                    title: "Şunları deneyebilirsin",
                    symbol: "sparkle.magnifyingglass",
                    items: Self.starterSuggestions
                )
                if !model.recentQueries.isEmpty {
                    suggestionSection(
                        title: "Son aramaların",
                        symbol: "clock.arrow.circlepath",
                        items: model.recentQueries
                    )
                }
            }
            .padding(Token.Space.lg)
        }
        .scrollIndicators(.hidden)
    }

    private func suggestionSection(
        title: String,
        symbol: String,
        items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.md) {
            Label(title, systemImage: symbol)
                .font(Token.Typography.headline)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: Token.Space.sm) {
                ForEach(items, id: \.self) { item in
                    Button {
                        Task { await model.apply(suggestion: item) }
                    } label: {
                        Text(item)
                            .font(Token.Typography.callout)
                            .padding(.horizontal, Token.Space.md)
                            .padding(.vertical, Token.Space.sm)
                            .background(.surface, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.pressable)
                    .frame(minHeight: Token.minimumTapTarget)
                }
            }
        }
    }

    // MARK: - Sonuçlar

    private func resultList(_ results: [SearchResult]) -> some View {
        ScrollView {
            LazyVStack(spacing: Token.Space.sm) {
                ForEach(results) { result in
                    NavigationLink(value: result) {
                        // Hücre ayrı görünüm: önizleme önbelleğini kendisi okur, böylece
                        // görsel geldiğinde tüm sonuç listesi değil yalnız satır yenilenir.
                        SearchResultCell(result: result, model: model)
                    }
                    .buttonStyle(.pressableCard)
                    .matchedTransitionSource(
                        id: result.shot.assetIdentifier, in: transitionNamespace
                    )
                    .task(id: result.shot.assetIdentifier) {
                        model.thumbnails.prefetch([result.shot.assetIdentifier])
                    }
                }
            }
            .padding(.horizontal, Token.Space.lg)
            .padding(.vertical, Token.Space.sm)
            .animation(Token.Motion.standard, value: results.map(\.id))
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
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

// MARK: - Alt görünümler

private struct SearchResultCell: View {
    let result: SearchResult
    let model: SearchViewModel

    var body: some View {
        SearchResultRow(result: result, image: model.image(for: result))
    }
}

/// Ayrıştırılan filtrelerin çip şeridi.
///
/// Modelin sorgudan **ne anladığı** görünür olmalı: sessizce uygulanan filtre,
/// kullanıcının anlamadığı boş sonuç demektir (02 §2.3).
private struct SearchFilterBar: View {
    let model: SearchViewModel

    var body: some View {
        if let intent = model.appliedIntent, intent.hasFilters {
            ScrollView(.horizontal) {
                HStack(spacing: Token.Space.sm) {
                    if let category = intent.category {
                        chip(
                            symbol: CategoryStyle.style(for: category).symbolName,
                            title: CategoryStyle.style(for: category).title
                        ) {
                            Task { await model.removeCategoryFilter() }
                        }
                    }
                    if let range = intent.dateRange {
                        chip(symbol: "calendar", title: SearchView.title(for: range)) {
                            Task { await model.removeDateFilter() }
                        }
                    }
                    if intent.minAmount != nil || intent.maxAmount != nil {
                        chip(symbol: "turkishlirasign.circle", title: amountTitle(intent)) {
                            Task { await model.removeAmountFilter() }
                        }
                    }
                }
                .padding(.horizontal, Token.Space.lg)
                .padding(.vertical, Token.Space.sm)
            }
            .scrollIndicators(.hidden)
            .background(.thinMaterial)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(Token.Motion.standard, value: intent)
        }
    }

    private func chip(
        symbol: String,
        title: String,
        onRemove: @escaping () -> Void
    ) -> some View {
        Button(action: onRemove) {
            HStack(spacing: Token.Space.xs) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(Token.Typography.caption)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Token.Space.md)
            .frame(minHeight: 32)
            .background(Color.accentColor.opacity(0.16), in: Capsule(style: .continuous))
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.pressable)
        .frame(minHeight: Token.minimumTapTarget)
        .accessibilityLabel("\(title) filtresini kaldır")
    }

    private func amountTitle(_ intent: SearchIntent) -> String {
        if let minimum = intent.minAmount { return "\(Int(minimum))+" }
        if let maximum = intent.maxAmount { return "\(Int(maximum))-" }
        return "tutar"
    }
}
