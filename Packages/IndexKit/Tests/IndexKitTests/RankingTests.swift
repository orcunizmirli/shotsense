import Foundation
import Testing
@testable import IndexKit

@Suite("Sıralama bileşenleri")
struct RankingTests {
    @Test("Tazelik puanı bugüne 1, yarılanma ölçeğinde ~0.37 verir")
    func recencyDecay() {
        let now = Date()
        #expect(abs(HybridIndex.recencyScore(for: now, now: now) - 1) < 0.001)

        let halfLife = now.addingTimeInterval(-HybridIndex.recencyDecayDays * 86400)
        #expect(abs(HybridIndex.recencyScore(for: halfLife, now: now) - exp(-1)) < 0.001)
    }

    @Test("Gelecek tarihli kayıt tazeliği 1'i aşmaz")
    func futureDateIsClamped() {
        // Cihaz saati değişimleri gelecek tarihli asset üretebilir; skor patlamamalı.
        let now = Date()
        #expect(HybridIndex.recencyScore(for: now.addingTimeInterval(86400), now: now) == 1)
    }

    @Test("Ağırlıklar toplamı 1")
    func weightsSumToOne() {
        let total = HybridIndex.Weight.term + HybridIndex.Weight.semantic + HybridIndex.Weight.recency
        #expect(abs(total - 1) < 0.0001)
    }

    @Test("Anlamsal bileşen yoksa ağırlığı terime devredilir")
    func semanticWeightFallsBackToTerm() {
        // Vektör modeli olmayan cihazda skor ölçeği değişmemeli, yoksa eşikler kayar.
        let total = HybridIndex.Weight.termWithoutSemantic + HybridIndex.Weight.recency
        #expect(abs(total - 1) < 0.0001)
    }

    @Test("Vektör birim uzunluğa normalize edilir")
    func vectorsAreNormalized() throws {
        let normalized = try #require(EmbeddingProvider.normalize([3, 4]))
        #expect(abs(normalized[0] - 0.6) < 0.0001)
        #expect(abs(normalized[1] - 0.8) < 0.0001)
    }

    @Test("Sıfır vektör normalize edilemez")
    func zeroVectorIsRejected() {
        #expect(EmbeddingProvider.normalize([0, 0]) == nil)
    }

    @Test("Aynı yöndeki vektörler 1, dik olanlar 0 benzerlik verir")
    func cosineSimilarity() {
        #expect(abs(EmbeddingProvider.similarity([1, 0], [1, 0]) - 1) < 0.0001)
        #expect(abs(EmbeddingProvider.similarity([1, 0], [0, 1])) < 0.0001)
    }

    @Test("Farklı boyuttaki vektörler karşılaştırılmaz")
    func mismatchedDimensionsYieldZero() {
        #expect(EmbeddingProvider.similarity([1, 0], [1, 0, 0]) == 0)
    }
}
