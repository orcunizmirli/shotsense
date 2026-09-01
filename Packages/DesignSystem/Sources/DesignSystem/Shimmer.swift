import SwiftUI

/// İskelet yüzeylerde gezinen parıltı.
///
/// Sabit gri bir dikdörtgen "donmuş" görünür; gezinen parıltı sistemin çalıştığını anlatır
/// ve algılanan bekleme süresini kısaltır. "Hareketi Azalt" açıkken parıltı durur —
/// sürekli tekrar eden hareket vestibüler rahatsızlık için en sorunlu türdür.
public struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    public func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.primary.opacity(0.10),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width * 1.6)
                    }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Token.Motion.ambient.repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

public extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}
