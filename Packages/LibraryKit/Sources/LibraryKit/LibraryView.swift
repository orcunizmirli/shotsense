import DesignSystem
import ShotCore
import SwiftUI

/// Kitaplık ızgarası (02 §2.2).
public struct LibraryView: View {
    @State private var model: LibraryViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var transitionNamespace

    private let dependencies: LibraryDependencies
    private let paywall: PaywallPresenter

    public init(dependencies: LibraryDependencies, paywall: PaywallPresenter) {
        self.dependencies = dependencies
        self.paywall = paywall
        _model = State(wrappedValue: LibraryViewModel(dependencies: dependencies))
    }

    public var body: some View {
        content
            .navigationTitle("Kitaplık")
            .navigationDestination(for: Shot.self) { shot in
                ShotDetailView(shot: shot, dependencies: dependencies, paywall: paywall)
                    // Izgaradaki karttan detaya büyüyen geçiş: kullanıcı hangi öğeye
                    // girdiğini gözden kaçırmaz ve geri dönüş yönü açıktır.
                    .navigationTransition(.zoom(sourceID: shot.assetIdentifier, in: transitionNamespace))
            }
            .task {
                await model.load()
                await model.startIndexing()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            skeletonGrid

        case .permissionRequired:
            // 02 §3: "izin yok" ile "sonuç yok" asla aynı ekranı göstermez.
            StateView(
                symbolName: "lock.open.rotation",
                title: "Fotoğraflara erişim gerekli",
                message: "Ekran görüntülerini cihazında indeksleyebilmemiz için erişim izni ver. "
                    + "Görsellerin telefonundan çıkmaz.",
                actionTitle: "İzin ver"
            ) {
                Task { await model.requestPermission() }
            }

        case .empty:
            StateView(
                symbolName: model.selectedCategory == nil
                    ? "photo.on.rectangle.angled" : "line.3.horizontal.decrease",
                title: model.selectedCategory == nil ? "Ekran görüntüsü yok" : "Bu kategoride yok",
                message: model.selectedCategory == nil
                    ? "Telefonunda ekran görüntüsü bulunamadı."
                    : "Başka bir kategori dene.",
                actionTitle: model.selectedCategory == nil ? nil : "Tümünü göster"
            ) {
                Task { await model.select(category: nil) }
            }

        case let .failed(message):
            StateView(
                symbolName: "exclamationmark.triangle",
                title: "Bir sorun oldu",
                message: message,
                actionTitle: "Tekrar dene"
            ) {
                Task { await model.reload() }
            }

        case let .content(shots):
            grid(shots)
        }
    }

    // MARK: - Izgara

    private var columnCount: Int {
        Token.gridColumns(for: dynamicTypeSize)
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Token.Space.md),
            count: columnCount
        )
    }

    private var skeletonGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Token.Space.lg) {
                ForEach(0 ..< 12, id: \.self) { _ in SkeletonCard() }
            }
            .padding(.horizontal, Token.Space.lg)
            .padding(.top, Token.Space.sm)
        }
        .scrollDisabled(true)
    }

    private func grid(_ shots: [Shot]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Token.Space.lg) {
                ForEach(shots) { shot in
                    NavigationLink(value: shot) {
                        // Hücre AYRI bir görünüm: önizleme önbelleğini kendisi okur.
                        // Okuma burada, kapsayıcının gövdesinde yapılsaydı her görsel
                        // gelişinde tüm ızgara (çipler, rozet, yerleşim) geçersizleşirdi.
                        LibraryCell(shot: shot, model: model)
                    }
                    .buttonStyle(.pressableCard)
                    .matchedTransitionSource(id: shot.assetIdentifier, in: transitionNamespace)
                    .task(id: shot.assetIdentifier) {
                        // Hücre görününce hem önizleme penceresi istenir hem de sayfalama
                        // tetiklenir; ikisi de ucuz ve kuyruklanmış işlerdir.
                        await model.cellAppeared(shot)
                    }
                }
            }
            .padding(.horizontal, Token.Space.lg)
            .padding(.top, Token.Space.sm)
            .padding(.bottom, Token.Space.xxxl)
            .animation(Token.Motion.standard, value: shots.count)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.reload() }
        .safeAreaInset(edge: .top, spacing: 0) {
            CategoryChipBar(model: model, namespace: transitionNamespace)
        }
        .overlay(alignment: .bottom) {
            IndexingBadgeOverlay(model: model)
        }
    }
}

// MARK: - Alt görünümler

/// Tek ızgara hücresi.
///
/// Ayrı bir `View` olmasının sebebi **gözlem kapsamıdır**: önizleme önbelleği burada
/// okunur, dolayısıyla önbellek değiştiğinde yalnız hücreler yeniden çizilir — kapsayıcı
/// ekran (çip şeridi, ilerleme rozeti, ızgara yerleşimi) el değmeden kalır.
private struct LibraryCell: View {
    let shot: Shot
    let model: LibraryViewModel

    var body: some View {
        ShotCard(shot: shot, image: model.image(for: shot))
    }
}

/// Kategori çip şeridi.
///
/// Kapsayıcıdan ayrılmıştır: kategori sayıları indeksleme sürerken değişir ve bu
/// değişimin ızgarayı yeniden kurması için hiçbir sebep yoktur.
private struct CategoryChipBar: View {
    let model: LibraryViewModel
    let namespace: Namespace.ID

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Token.Space.sm) {
                chip(title: "Tümü", count: nil, category: nil)
                ForEach(model.categoryCounts, id: \.category) { entry in
                    chip(
                        title: CategoryStyle.style(for: entry.category).title,
                        count: entry.count,
                        category: entry.category
                    )
                }
            }
            .padding(.horizontal, Token.Space.lg)
            .padding(.vertical, Token.Space.sm)
        }
        .scrollIndicators(.hidden)
        // Çip şeridi içeriğin üstünde yüzer; arkasındaki ızgara kaydıkça bulanıklaşır.
        .background(.bar)
        .animation(Token.Motion.standard, value: model.categoryCounts.map(\.category))
    }

    private func chip(title: String, count: Int?, category: ShotCategory?) -> some View {
        let isSelected = model.selectedCategory == category

        return Button {
            Task { await model.select(category: category) }
        } label: {
            HStack(spacing: Token.Space.xs) {
                Text(title)
                    .font(Token.Typography.caption)
                if let count {
                    Text("\(count)")
                        .font(Token.Typography.micro)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(count)))
                }
            }
            .fontWeight(isSelected ? .semibold : .regular)
            .padding(.horizontal, Token.Space.md)
            .frame(minHeight: 34)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                        // Seçim vurgusu çipler arasında kayar; anlık geçiş yerine hareket
                        // kullanıcının hangi çipten hangisine geçtiğini gösterir.
                        .matchedGeometryEffect(id: "chip.selection", in: namespace)
                } else {
                    Capsule(style: .continuous).fill(.surface)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.pressable)
        .frame(minHeight: Token.minimumTapTarget)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(count.map { "\(title), \($0) öğe" } ?? title)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// İndeksleme ilerleme rozeti.
///
/// Ayrı görünüm: ilerleme saniyede birkaç kez güncellenir; bu okumayı kapsayıcıda
/// bırakmak her güncellemede tüm ızgarayı yeniden çizdirirdi.
private struct IndexingBadgeOverlay: View {
    let model: LibraryViewModel

    var body: some View {
        if let progress = model.progress, progress.isRunning, progress.total > 0 {
            IndexingBadge(analyzed: progress.analyzed, total: progress.total)
                .padding(.bottom, Token.Space.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(Token.Motion.standard, value: progress.analyzed)
        }
    }
}
