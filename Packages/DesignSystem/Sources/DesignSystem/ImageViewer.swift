import CoreGraphics
import SwiftUI

/// Tam ekran görsel inceleyici: çift dokunuşla ve kıstırarak yakınlaştırma, aşağı
/// sürükleyerek kapatma.
///
/// Ekran görüntüsü uygulamasında bu ekran **çekirdek işlevdir**: kullanıcı çoğu zaman
/// küçük punto bir bilgiyi (kod, tarih, adres) okumak için gelir. Yakınlaştırma olmadan
/// ürün amacını karşılamaz.
public struct ImageViewer: View {
    private let image: CGImage?
    private let onDismiss: () -> Void

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var dismissProgress: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maximumScale: CGFloat = 6

    public init(image: CGImage?, onDismiss: @escaping () -> Void) {
        self.image = image
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Kapatma sürüklemesi ilerledikçe zemin şeffaflaşır: kullanıcı hareketin
            // geri alınabilir olduğunu görür.
            Color.black.opacity(1 - dismissProgress * 0.7).ignoresSafeArea()

            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnification)
                    .simultaneousGesture(panOrDismiss)
                    .onTapGesture(count: 2, perform: toggleZoom)
            }
        }
        .overlay(alignment: .topTrailing) { closeButton }
        // Durum çubuğu yalnız iOS'ta gizlenir; macOS'ta böyle bir kavram yok ve API
        // orada kullanılamaz olarak işaretli. Paket macOS'ta da derlensin diye ayrılır.
        #if os(iOS)
        .statusBarHidden()
        #endif
        .accessibilityAction(named: "Kapat", onDismiss)
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: Token.minimumTapTarget, height: Token.minimumTapTarget)
                .background(.black.opacity(0.35), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.pressable)
        .padding(Token.Space.lg)
        .accessibilityLabel("Kapat")
    }

    // MARK: - Hareketler

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(committedScale * value.magnification, 1), maximumScale)
            }
            .onEnded { _ in
                committedScale = scale
                if scale <= 1.01 { resetPosition() }
            }
    }

    /// Yakınlaştırılmışken kaydırır, normal boyutta aşağı çekince kapatır.
    ///
    /// İki hareketi ayırmak gerekir: yakınlaştırılmış görselde aşağı sürükleme "gezinme",
    /// normal boyutta "kapat" demektir. Ayrım yapılmazsa kullanıcı görseli incelerken
    /// ekran kapanır.
    private var panOrDismiss: some Gesture {
        DragGesture()
            .onChanged { value in
                if committedScale > 1 {
                    offset = CGSize(
                        width: committedOffset.width + value.translation.width,
                        height: committedOffset.height + value.translation.height
                    )
                } else if value.translation.height > 0 {
                    offset = CGSize(width: 0, height: value.translation.height)
                    dismissProgress = min(value.translation.height / 260, 1)
                }
            }
            .onEnded { value in
                if committedScale > 1 {
                    committedOffset = offset
                    return
                }
                if value.translation.height > 140 {
                    onDismiss()
                } else {
                    withAnimation(animation) { resetPosition() }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(animation) {
            if committedScale > 1 {
                resetPosition()
            } else {
                scale = 2.5
                committedScale = 2.5
            }
        }
    }

    private func resetPosition() {
        scale = 1
        committedScale = 1
        offset = .zero
        committedOffset = .zero
        dismissProgress = 0
    }

    private var animation: Animation? {
        Token.Motion.respectingReduceMotion(Token.Motion.standard, isReduced: reduceMotion)
    }
}
