import AppFoundation
import ShotCore
import SwiftUI

/// Çıkarılan bir bilginin detay ekranındaki satırı.
///
/// Hassas türler (IBAN, wifi şifresi, doğrulama kodu) **varsayılan olarak maskelenir**
/// (KANON §7): kullanıcı ekran görüntüsü alırken veya birine telefonu gösterirken bu
/// değerlerin açıkta olmaması gerekir. Dokununca açılır.
public struct EntityRow: View {
    private let entity: ExtractedEntity
    private let onCopy: (String) -> Void
    private let onAction: ((ExtractedEntity) -> Void)?

    @State private var isRevealed = false
    @State private var didCopy = false

    public init(
        entity: ExtractedEntity,
        onCopy: @escaping (String) -> Void,
        onAction: ((ExtractedEntity) -> Void)? = nil
    ) {
        self.entity = entity
        self.onCopy = onCopy
        self.onAction = onAction
    }

    public var body: some View {
        HStack(spacing: Token.Space.md) {
            icon
            labels
            Spacer(minLength: Token.Space.sm)
            controls
        }
        .padding(.vertical, Token.Space.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private var icon: some View {
        Image(systemName: Self.symbolName(for: entity.kind))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.tint)
            .frame(width: 34, height: 34)
            .background(Color.accentColor.opacity(0.12), in: Circle())
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(Self.title(for: entity.kind))
                .font(Token.Typography.micro)
                .foregroundStyle(.secondary)
            Text(displayValue)
                .font(Token.Typography.numeric)
                .textSelection(.enabled)
                .lineLimit(2)
                // Maskeden açığa geçiş ani olmaz: değerin değiştiği fark edilir.
                .contentTransition(.opacity)
        }
    }

    private var controls: some View {
        HStack(spacing: Token.Space.xs) {
            if entity.kind.isSensitive {
                iconButton(
                    systemName: isRevealed ? "eye.slash" : "eye",
                    label: isRevealed ? "Gizle" : "Göster"
                ) {
                    withAnimation(Token.Motion.quick) { isRevealed.toggle() }
                }
            }

            iconButton(
                systemName: didCopy ? "checkmark" : "doc.on.doc",
                label: "Kopyala",
                tint: didCopy ? .green : .secondary
            ) {
                onCopy(entity.rawValue)
                withAnimation(Token.Motion.quick) { didCopy = true }
            }
            // Onay işareti kalıcı olmaz: kısa bir doğrulama sonrası eski hâline döner.
            .task(id: didCopy) {
                guard didCopy else { return }
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(Token.Motion.standard) { didCopy = false }
            }
            .sensoryFeedback(.success, trigger: didCopy)

            if entity.kind.isActionable, let onAction {
                iconButton(systemName: "arrow.up.forward", label: "Aksiyona çevir") {
                    onAction(entity)
                }
            }
        }
    }

    private func iconButton(
        systemName: String,
        label: String,
        tint: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: Token.minimumTapTarget, height: Token.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }

    private var displayValue: String {
        guard entity.kind.isSensitive, !isRevealed else { return entity.rawValue }
        return Redaction.mask(entity.rawValue, visibleSuffix: entity.kind == .iban ? 4 : 0)
    }

    public static func title(for kind: EntityKind) -> String {
        switch kind {
        case .date: return "Tarih"
        case .amount: return "Tutar"
        case .merchant: return "Satıcı"
        case .url: return "Bağlantı"
        case .phone: return "Telefon"
        case .email: return "E-posta"
        case .iban: return "IBAN"
        case .trackingNumber: return "Takip no"
        case .flightNumber: return "Uçuş"
        case .address: return "Adres"
        case .wifiSSID: return "Ağ adı"
        case .wifiPassword: return "Şifre"
        case .code: return "Kod"
        case .person: return "Kişi"
        }
    }

    public static func symbolName(for kind: EntityKind) -> String {
        switch kind {
        case .date: return "calendar"
        case .amount: return "turkishlirasign.circle"
        case .merchant: return "storefront"
        case .url: return "link"
        case .phone: return "phone"
        case .email: return "envelope"
        case .iban: return "building.columns"
        case .trackingNumber: return "shippingbox"
        case .flightNumber: return "airplane"
        case .address: return "mappin"
        case .wifiSSID: return "wifi"
        case .wifiPassword: return "key"
        case .code: return "number"
        case .person: return "person"
        }
    }
}
