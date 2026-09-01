import DesignSystem
import ShotCore
import SwiftUI

/// Kitaplık ızgarası (02 §2.2).
public struct LibraryView: View {
    @State private var model: LibraryViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                symbolName: "lock",
                title: "Fotoğraflara erişim gerekli",
                message: "Ekran görüntülerini cihazında indeksleyebilmemiz için erişim izni ver. "
                    + "Görsellerin telefonundan çıkmaz.",
                actionTitle: "İzin ver"
            ) {
                Task { await model.requestPermission() }
            }
        case .empty:
            StateView(
                symbolName: "photo.on.rectangle.angled",
                title: model.selectedCategory == nil ? "Ekran görüntüsü yok" : "Bu kategoride yok",
                message: model.selectedCategory == nil
                    ? "Telefonunda ekran görüntüsü bulunamadı."
                    : "Başka bir kategori dene."
            )
        case let .failed(message):
            StateView(
                symbolName: "exclamationmark.triangle",
                title: "Bir sorun oldu",
                message: LocalizedStringKey(message),
                actionTitle: "Tekrar dene"
            ) {
                Task { await model.reload() }
            }
        case let .content(shots):
            grid(shots)
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Token.Space.sm),
            count: Token.gridColumns(for: dynamicTypeSize)
        )
    }

    private var skeletonGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Token.Space.md) {
                ForEach(0 ..< 9, id: \.self) { _ in SkeletonCard() }
            }
            .padding(Token.Space.lg)
        }
    }

    private func grid(_ shots: [Shot]) -> some View {
        VStack(spacing: 0) {
            if let progress = model.progress, progress.isRunning || progress.fraction < 1 {
                ProgressBanner(analyzed: progress.analyzed, total: progress.total)
            }
            categoryChips
            ScrollView {
                LazyVGrid(columns: columns, spacing: Token.Space.md) {
                    ForEach(shots) { shot in
                        NavigationLink {
                            ShotDetailView(
                                shot: shot, dependencies: dependencies, paywall: paywall
                            )
                        } label: {
                            ShotCard(shot: shot, thumbnailData: model.thumbnail(for: shot))
                        }
                        .buttonStyle(.plain)
                        .task {
                            await model.loadThumbnail(for: shot)
                            await model.loadMoreIfNeeded(currentItem: shot)
                        }
                    }
                }
                .padding(Token.Space.lg)
            }
            .refreshable { await model.reload() }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Token.Space.sm) {
                chip(title: "Tümü", isSelected: model.selectedCategory == nil) {
                    Task { await model.select(category: nil) }
                }
                ForEach(model.availableCategories, id: \.self) { category in
                    let style = CategoryStyle.style(for: category)
                    chip(title: style.title, isSelected: model.selectedCategory == category) {
                        Task { await model.select(category: category) }
                    }
                }
            }
            .padding(.horizontal, Token.Space.lg)
            .padding(.vertical, Token.Space.sm)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, Token.Space.md)
                .padding(.vertical, Token.Space.sm)
                .background(isSelected ? Color.accentColor.opacity(0.2) : .surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: Token.minimumTapTarget)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
