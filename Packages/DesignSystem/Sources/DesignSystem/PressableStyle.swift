import SwiftUI

/// Dokunulduğunda hafifçe küçülen ve sönen düğme stili.
///
/// **Neden:** iOS'ta bir öğenin dokunmaya yanıt verdiğini gösteren tek şey bu geri
/// bildirimdir. `.buttonStyle(.plain)` ile hiçbir yanıt vermeyen kart, kullanıcıya
/// "dokunma algılanmadı" hissi verir ve tekrar dokunmasına yol açar.
///
/// Ölçek 0.97'de tutulur: daha fazlası oyuncak gibi görünür, daha azı hissedilmez.
public struct PressableButtonStyle: ButtonStyle {
    private let scale: CGFloat
    private let opacity: Double

    public init(scale: CGFloat = 0.97, opacity: Double = 0.85) {
        self.scale = scale
        self.opacity = opacity
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? opacity : 1)
            .animation(Token.Motion.quick, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
    /// Kartlar için daha ölçülü basış (büyük yüzeyde 0.97 fazla gelir).
    static var pressableCard: PressableButtonStyle {
        PressableButtonStyle(scale: 0.985, opacity: 0.92)
    }
}

/// Birincil eylem düğmesi: dolu, vurgulu, tam genişlik.
public struct ProminentActionStyle: ButtonStyle {
    private let tint: Color

    public init(tint: Color = .accentColor) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Token.Typography.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                tint.gradient,
                in: RoundedRectangle(cornerRadius: Token.Radius.md, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Token.Motion.quick, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == ProminentActionStyle {
    static var prominentAction: ProminentActionStyle { ProminentActionStyle() }
}

/// İkincil eylem düğmesi: yüzey zeminli, kenarlıklı.
public struct SecondaryActionStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Token.Typography.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .surfaceCard(radius: Token.Radius.md)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Token.Motion.quick, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == SecondaryActionStyle {
    static var secondaryAction: SecondaryActionStyle { SecondaryActionStyle() }
}
