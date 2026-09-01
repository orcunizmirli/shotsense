import DesignSystem
import ShotCore
import SwiftUI

/// Detay ekranı (02 §2.4).
public struct ShotDetailView: View {
    @State private var model: ShotDetailViewModel
    @State private var isTextExpanded = false
    @State private var isCategoryPickerPresented = false
    @Environment(\.dismiss) private var dismiss

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
                ThumbnailImage(data: model.fullImageData ?? model.thumbnailData)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 420)

                header
                if !model.shot.analysis.summary.isEmpty { summaryCard }
                if !model.entities.isEmpty { entitiesSection }
                textSection
                actions
            }
            .padding(Token.Space.lg)
        }
        .navigationTitle(model.shot.analysis.title.isEmpty ? "Detay" : model.shot.analysis.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .alert("Bir sorun oldu", isPresented: errorBinding) {
            Button("Tamam") { model.clearToast() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.subheadline)
                    .padding(Token.Space.md)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, Token.Space.xl)
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        model.clearToast()
                    }
            }
        }
        .confirmationDialog("Kategori", isPresented: $isCategoryPickerPresented) {
            ForEach(ShotCategory.allCases, id: \.self) { category in
                Button(CategoryStyle.style(for: category).title) {
                    Task { await model.correctCategory(to: category) }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            CategoryBadge(category: model.shot.analysis.category)
            Text(model.shot.createdAt, format: .dateTime.day().month().year())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if model.shot.analysis.analyzerKind == .heuristic {
                // Kullanıcı özetin nereden geldiğini bilmeli: heuristik sonuç LLM'inki kadar
                // iyi değildir ve bunu gizlemek güveni zedeler (KANON §5).
                Image(systemName: "cpu")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Temel analiz")
            }
        }
    }

    private var summaryCard: some View {
        Text(model.shot.analysis.summary)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Token.Space.md)
            .background(.surface, in: RoundedRectangle(cornerRadius: Token.Radius.md))
    }

    private var entitiesSection: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            Text("Çıkarılan bilgiler")
                .font(.headline)
            ForEach(model.entities) { entity in
                EntityRow(entity: entity) { value in
                    clipboard.copy(value, isSensitive: entity.kind.isSensitive)
                }
                Divider()
            }
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            Button {
                isTextExpanded.toggle()
            } label: {
                HStack {
                    Text("Metin").font(.headline)
                    Spacer()
                    Image(systemName: isTextExpanded ? "chevron.up" : "chevron.down")
                }
            }
            .buttonStyle(.plain)
            .frame(minHeight: Token.minimumTapTarget)

            if isTextExpanded {
                Text(model.shot.recognizedText)
                    .font(.footnote)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Token.Space.sm) {
            if model.actionableDate != nil {
                Button {
                    Task { await model.createReminder() }
                } label: {
                    Label("Hatırlatıcı kur", systemImage: "bell")
                        .frame(maxWidth: .infinity, minHeight: Token.minimumTapTarget)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await model.createCalendarEvent() }
                } label: {
                    Label("Takvime ekle", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: Token.minimumTapTarget)
                }
                .buttonStyle(.bordered)
            }

            Button {
                isCategoryPickerPresented = true
            } label: {
                Label("Yanlış mı? Düzelt", systemImage: "pencil")
                    .frame(maxWidth: .infinity, minHeight: Token.minimumTapTarget)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                Task {
                    await model.removeFromLibrary()
                    dismiss()
                }
            } label: {
                // Metin bilinçli olarak "sil" değil: fotoğraf silinmiyor (05 §6).
                Label("Kitaplıktan kaldır", systemImage: "eye.slash")
                    .frame(maxWidth: .infinity, minHeight: Token.minimumTapTarget)
            }
            .buttonStyle(.bordered)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearToast() } }
        )
    }
}
