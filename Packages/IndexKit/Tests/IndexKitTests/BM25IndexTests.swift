import Testing
@testable import IndexKit

@Suite("BM25Index")
struct BM25IndexTests {
    private struct Document {
        let id: String
        let title: String
        let body: String
    }

    private func index(_ documents: [Document]) -> BM25Index {
        var index = BM25Index()
        for document in documents {
            index.index(
                documentID: document.id, title: document.title, body: document.body, tags: []
            )
        }
        return index
    }

    @Test("Başlıkta geçen terim gövdede geçenden yüksek skorlanır")
    func titleBoostWins() {
        // "kulaklık" araması, kelimeyi başlığında taşıyan ürün ekranını, kelimeyi bir kez
        // geçen uzun makaleden öne çıkarmalı.
        let index = index([
            Document(id: "urun", title: "Bluetooth Kulaklık", body: "sepete ekle stokta"),
            Document(
                id: "makale",
                title: "Teknoloji Haberleri",
                body: String(repeating: "metin ", count: 200) + "kulaklık"
            ),
        ])
        let scores = index.scores(for: "kulaklık")
        #expect((scores["urun"] ?? 0) > (scores["makale"] ?? 0))
    }

    @Test("Her belgede geçen terim ayırt etmez")
    func commonTermHasLowIdf() {
        let index = index([
            Document(id: "a", title: "", body: "toplam kulaklık"),
            Document(id: "b", title: "", body: "toplam kitap"),
            Document(id: "c", title: "", body: "toplam masa"),
        ])
        let common = index.scores(for: "toplam")
        let rare = index.scores(for: "kulaklık")
        #expect((common["a"] ?? 0) < (rare["a"] ?? 0))
    }

    @Test("Eşleşmeyen belge sonuç kümesine hiç girmez")
    func nonMatchingDocumentsAreExcluded() {
        let index = index([
            Document(id: "a", title: "", body: "kulaklık"),
            Document(id: "b", title: "", body: "masa"),
        ])
        let scores = index.scores(for: "kulaklık")
        #expect(scores["b"] == nil)
    }

    @Test("Aynı kimlikle yeniden indeksleme eskisini değiştirir")
    func reindexingReplaces() {
        var index = BM25Index()
        index.index(documentID: "a", title: "eski", body: "kulaklık", tags: [])
        index.index(documentID: "a", title: "yeni", body: "masa", tags: [])

        #expect(index.documentCount == 1)
        #expect(index.scores(for: "kulaklık").isEmpty)
        #expect(index.scores(for: "masa")["a"] != nil)
    }

    @Test("Silme belgeyi tüm sonuçlardan çıkarır")
    func removalClearsPostings() {
        var index = BM25Index()
        index.index(documentID: "a", title: "", body: "kulaklık", tags: [])
        index.remove(documentID: "a")

        #expect(index.documentCount == 0)
        #expect(index.scores(for: "kulaklık").isEmpty)
    }

    @Test("Etiketler aranabilir")
    func tagsAreSearchable() {
        var index = BM25Index()
        index.index(documentID: "a", title: "Başlık", body: "gövde", tags: ["fatura"])
        #expect(index.scores(for: "fatura")["a"] != nil)
    }

    @Test("Türkçe büyük harf farkı aramayı bozmaz")
    func caseFoldingWorks() {
        var index = BM25Index()
        index.index(documentID: "a", title: "MİGROS", body: "", tags: [])
        #expect(index.scores(for: "migros")["a"] != nil)
    }

    @Test("Boş indekste arama boş döner")
    func emptyIndexReturnsNothing() {
        #expect(BM25Index().scores(for: "kulaklık").isEmpty)
    }

    @Test("Normalizasyon en yüksek skoru 1 yapar")
    func normalizationScalesToOne() {
        let normalized = BM25Index.normalized(["a": 4, "b": 2])
        #expect(normalized["a"] == 1)
        #expect(normalized["b"] == 0.5)
    }
}
