import DesignSystem
import ShotCore
import SwiftUI

/// Detay ekranı (02 §2.4).
public struct ShotDetailView: View {
    @State private var model: ShotDetailViewModel
    @State private var isTextExpanded = false
    @State private var isViewerPresented = false
    @State private var isCategoryPickerPresented = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let clipboard: any ClipboardWriting

    public init(shot: Shot, dependencies: LibraryDependencies, paywall: PaywallPresenter) {
        clipboard = dependencies.clipboard
        _model = State(
            wrappedValue: ShotDetailViewModel(
                shot: shot, dependencies: dependencies, paywall: paywall
            )
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Token.Space.lg) {
                hero
                header
                if !model.shot.analysis.summary.isEmpty { summaryCard }
                if !model.entities.isEmpty { entitiesCard }
                textCard
            }
            .padding(.horizontal, Token.Space.lg)
            .padding(.bottom, 96) // yüzen aksiyon çubuğu için yer
        }
        .scrollIndicators(.hidden)
        .navigationTitle(model.shot.analysis.title.isEmpty ? "Detay" : model.shot.analysis.title)
        .inlineTitle()
        .toolbar { toolbarMenu }
        .task { await model.load() }
        .overlay(alignment: .bottom) { actionBar }
        .overlay(alignment: .bottom) { toast }
        .fullScreenPresentation(isPresented: $isViewerPresented) {
            ImageViewer(image: model.displayImage) { isViewerPresented = false }
        }
        .alert("Bir sorun oldu", isPresented: errorBinding) {
            Button("Tamam") { model.clearToast() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(
            "Doğru kategori hangisi?",
            isPresented: $isCategoryPickerPresented,
            titleVisibility: .visible
        ) {
            ForEach(ShotCategory.allCases, id: \.self) { category in
                Button(CategoryStyle.style(for: category).title) {
                    Task { await model.correctCategory(to: category) }
                }
            }
        }
    }

    // MARK: - Görsel

    private var hero: some View {
        Button {
            isViewerPresented = true
        } label: {
            ThumbnailImage(image: model.displayImage, cornerRadius: Token.Radius.lg)
                .aspectRatio(9 / 16, contentMode: .fit)
                .frame(maxHeight: 380)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    // Yakınlaştırılabilirlik keşfedilebilir olmalı: ipucu olmadan
                    // kullanıcı görsele dokunmayı denemez.
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(Token.Space.sm)
                        .background(.black.opacity(0.35), in: Circle())
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(Token.Space.md)
                }
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel("Ekran görüntüsünü tam ekranda aç")
    }

    // MARK: - Başlık

    private var header: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            Text(model.shot.analysis.title.isEmpty ? "Başlıksız" : model.shot.analysis.title)
                .font(Token.Typography.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Token.Space.sm) {
                CategoryBadge(category: model.shot.analysis.category)
                Text(model.shot.createdAt, format: .dateTime.day().month().year())
                    .font(Token.Typography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.shot.analysis.analyzerKind == .heuristic {
                    // Kullanıcı özetin nereden geldiğini bilmeli: heuristik sonuç LLM'inki
                    // kadar iyi değildir ve bunu gizlemek güveni zedeler (KANON §5).
                    Label("Temel", systemImage: "cpu")
                        .font(Token.Typography.micro)
                        .foregroundStyle(.tertiary)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    // MARK: - Kartlar

    private var summaryCard: some View {
        Text(model.shot.analysis.summary)
            .font(Token.Typography.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Token.Space.lg)
            .surfaceCard()
    }

    private var entitiesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Çıkarılan bilgiler")
                .font(Token.Typography.headline)
                .padding(.bottom, Token.Space.sm)

            ForEach(Array(model.entities.enumerated()), id: \.element.id) { index, entity in
                EntityRow(entity: entity) { value in
                    clipboard.copy(value, isSensitive: entity.kind.isSensitive)
                    model.showToast("Kopyalandı")
                } onAction: { entity in
                    if let url = model.actionURL(for: entity) {
                        openURL(url)
                    } else {
                        Task { await model.performAction(for: entity) }
                    }
                }
                if index < model.entities.count - 1 {
                    Divider().padding(.leading, 46)
                }
            }
        }
        .padding(Token.Space.lg)
        .surfaceCard()
    }

    private var textCard: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            Button {
                withAnimation(Token.Motion.standard) { isTextExpanded.toggle() }
            } label: {
                HStack {
                    Text("Tanınan metin").font(Token.Typography.headline)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isTextExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .frame(minHeight: Token.minimumTapTarget)
            .accessibilityLabel(isTextExpanded ? "Metni gizle" : "Metni göster")

            if isTextExpanded {
                Text(model.shot.recognizedText)
                    .font(Token.Typography.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Token.Space.lg)
        .surfaceCard()
    }

    // MARK: - Aksiyonlar

    @ViewBuilder
    private var actionBar: some View {
        if model.actionableDate != nil {
            HStack(spacing: Token.Space.sm) {
                Button {
                    Task { await model.createReminder() }
                } label: {
                    Label("Hatırlatıcı", systemImage: "bell")
                        .font(Token.Typography.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.pressable)
                .foregroundStyle(Color.accentColor)

                Divider().frame(height: 24)

                Button {
                    Task { await model.createCalendarEvent() }
                } label: {
                    Label("Takvim", systemImage: "calendar.badge.plus")
                        .font(Token.Typography.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.pressable)
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, Token.Space.md)
            .padding(.vertical, Token.Space.sm)
            .floatingPanel()
            .padding(.horizontal, Token.Space.lg)
            .padding(.bottom, Token.Space.md)
            .sensoryFeedback(.success, trigger: model.toast)
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let message = model.toast {
            ToastView(message: message)
                .padding(.bottom, model.actionableDate != nil ? 96 : Token.Space.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(2))
                    model.clearToast()
                }
        }
    }

    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    isCategoryPickerPresented = true
                } label: {
                    Label("Kategoriyi düzelt", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    Task {
                        await model.removeFromLibrary()
                        dismiss()
                    }
                } label: {
                    // Metin bilinçli olarak "sil" değil: fotoğraf silinmiyor (05 §6).
                    Label("Kitaplıktan kaldır", systemImage: "eye.slash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Daha fazla")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearToast() } }
        )
    }
}
