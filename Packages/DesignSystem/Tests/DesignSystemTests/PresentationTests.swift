import ShotCore
import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Sunum eşlemeleri")
struct PresentationTests {
    @Test("Her kategorinin adı, ikonu ve rengi tanımlı", arguments: ShotCategory.allCases)
    func everyCategoryHasStyle(_ category: ShotCategory) {
        // Eksik bir eşleme derleme hatası vermez ama arayüzde boş rozet gösterir.
        let style = CategoryStyle.style(for: category)
        #expect(!style.title.isEmpty)
        #expect(!style.symbolName.isEmpty)
    }

    @Test("Her varlık türünün adı ve ikonu tanımlı", arguments: EntityKind.allCases)
    func everyEntityKindHasPresentation(_ kind: EntityKind) {
        #expect(!EntityRow.title(for: kind).isEmpty)
        #expect(!EntityRow.symbolName(for: kind).isEmpty)
    }

    @Test("Izgara büyük puntoda daralır")
    func gridNarrowsForLargeType() {
        // Dynamic Type XXL'de 3 sütunlu ızgarada başlıklar okunamaz hâle gelir (02 §4).
        #expect(Token.gridColumns(for: .large) == 3)
        #expect(Token.gridColumns(for: .xxLarge) == 2)
        #expect(Token.gridColumns(for: .accessibility3) == 1)
    }

    @Test("Dokunma hedefi asgari 44 pt")
    func tapTargetMeetsGuideline() {
        #expect(Token.minimumTapTarget >= 44)
    }
}
