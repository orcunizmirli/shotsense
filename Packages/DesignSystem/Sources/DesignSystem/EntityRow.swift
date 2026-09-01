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
            Image(systemName: Self.symbolName(for: entity.kind))
                .frame(width: 24)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: entity.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(displayValue)
                    .font(.body.monospacedDigit())
                    .textSelection(.enabled)
            }

            Spacer(minLength: Token.Space.sm)

            if entity.kind.isSensitive {
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .frame(minWidth: Token.minimumTapTarget, minHeight: Token.minimumTapTarget)
                .accessibilityLabel(isRevealed ? "Gizle" : "Göster")
            }

            Button {
                onCopy(entity.rawValue)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .frame(minWidth: Token.minimumTapTarget, minHeight: Token.minimumTapTarget)
            .accessibilityLabel("Kopyala")

            if entity.kind.isActionable, let onAction {
                Button {
                    onAction(entity)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .frame(minWidth: Token.minimumTapTarget, minHeight: Token.minimumTapTarget)
                .accessibilityLabel("Aksiyona çevir")
            }
        }
        .padding(.vertical, Token.Space.xs)
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
