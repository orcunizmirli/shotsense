import Testing
@testable import IndexKit

@Suite("SnippetBuilder")
struct SnippetBuilderTests {
    private let text = """
    Geri Paylaş Ayarlar
    Sipariş Özeti Bluetooth Kulaklık siyah renk
    Kargo bedava Toplam 1.299,00 TL
    """

    @Test("Parça eşleşen terimin çevresinden kesilir")
    func excerptSurroundsMatch() {
        let snippet = SnippetBuilder.snippet(for: "kulaklık", in: text, contextLength: 20)
        #expect(snippet.lowercased().contains("kulaklık"))
        // Baştaki arayüz gürültüsü ("Geri Paylaş") sonuca girmemeli.
        #expect(!snippet.hasPrefix("Geri"))
    }

    @Test("Kesilen parça üç nokta ile işaretlenir")
    func truncationIsMarked() {
        let snippet = SnippetBuilder.snippet(for: "kulaklık", in: text, contextLength: 10)
        #expect(snippet.contains("…"))
    }

    @Test("Eşleşme yoksa baştan kesilir")
    func fallsBackToPrefix() {
        let snippet = SnippetBuilder.snippet(for: "bulunmayanterim", in: text, contextLength: 20)
        #expect(snippet.hasPrefix("Geri"))
    }

    @Test("Boş sorgu ve boş metin çökmez")
    func handlesEmptyInput() {
        #expect(SnippetBuilder.snippet(for: "", in: text).isEmpty == false)
        #expect(SnippetBuilder.snippet(for: "kulaklık", in: "").isEmpty)
    }

    @Test("En ayırt edici (en uzun) terim tercih edilir")
    func prefersLongestTerm() {
        // "tl" her fişte geçer; "kulaklık" bu sonucu açıklayan terimdir.
        let snippet = SnippetBuilder.snippet(for: "tl kulaklık", in: text, contextLength: 15)
        #expect(snippet.lowercased().contains("kulaklık"))
    }
}
