# 05 — Veri Modeli ve Kalıcılık

## 1. Depolama seçimi

**SwiftData** (iOS 26). Gerekçe: `@Model` + `@Query` ile SwiftUI entegrasyonu, `ModelActor` ile
Swift 6 uyumlu izolasyon, migration desteği. Tam metin araması SwiftData'da yok → BM25 indeksi
**ayrı, kendi yazdığımız yapı** olarak tutulur (`IndexKit`), diskte tek bir binary snapshot
(`index.bin`) + bellekte posting list.

Görseller **kopyalanmaz** — yalnızca `PHAsset.localIdentifier` referansı ve 320px thumbnail
saklanır. Kullanıcı Photos'tan silerse kayıt "yetim" işaretlenir ve temizlenir.

## 2. Modeller

```swift
@Model final class ShotRecord {
    #Unique<ShotRecord>([\.assetIdentifier])
    var assetIdentifier: String        // PHAsset.localIdentifier
    var createdAt: Date                // asset'in çekilme tarihi
    var indexedAt: Date?
    var status: AnalysisStatus         // pending | analyzing | analyzed | failed | orphaned
    var schemaVersion: Int             // AnalysisSchemaVersion — yeniden analiz tetikler
    var pixelWidth: Int
    var pixelHeight: Int

    // OCR
    var recognizedText: String
    var ocrLanguages: [String]
    var barcodePayloads: [String]

    // Analiz
    var category: ShotCategory
    var categoryConfidence: Double
    var title: String
    var summary: String
    var tags: [String]
    var analyzerKind: AnalyzerKind     // foundationModel | heuristic
    var userCorrected: Bool

    // Türev
    var embedding: [Float]?            // 512-boyut, nil = model yok
    var thumbnailData: Data?           // 320px JPEG
    var perceptualHash: UInt64         // yinelenen tespiti (P1)

    // Varlıklar ayrı bir @Model değil, JSON blob'u olarak saklanır: her zaman kaydın
    // tamamıyla birlikte okunurlar, hiçbir zaman tek başlarına sorgulanmazlar. Ayrı tablo
    // yalnız ilişki göçü maliyeti getirirdi.
    var entitiesData: Data              // [ExtractedEntity] JSON'u
}

@Model final class ExtractedEntity {
    var kind: EntityKind               // date | amount | merchant | url | phone | email |
                                       // iban | trackingNumber | flightNumber | address |
                                       // wifiSSID | wifiPassword | code | person
    var rawValue: String               // metinde geçtiği hali
    var normalizedValue: String        // ISO tarih, ondalık tutar, E.164 telefon…
    var currencyCode: String?
    var confidence: Double
    var isGrounded: Bool               // OCR metninde doğrulandı mı (04 §5)
    var sourceRange: Range<Int>?       // recognizedText içindeki konum → vurgulama
}

@Model final class Collection {
    var name: String
    var symbolName: String             // SF Symbol
    var isSmart: Bool
    var savedQueryData: Data?          // akıllı koleksiyon için kodlanmış SearchQuery
    var shots: [ShotRecord]
}

@Model final class AnalysisJob {           // dayanıklı kuyruk (uygulama kapansa da sürsün)
    var assetIdentifier: String
    var attempts: Int
    var lastError: String?
    var nextAttemptAt: Date
    var priority: Int                       // 0 = kullanıcı tetikledi, 1 = yeni, 2 = geriye dönük
}
```

## 3. Domain ↔ kalıcılık ayrımı

`ShotRecord` bir **kalıcılık detayıdır** ve `IndexKit` içinde yaşar. `ShotCore` saf `struct Shot`
kullanır. Dönüşüm `ShotMapper` ile tek yönde yapılır. Bunun sebebi R1 kuralı: domain SwiftData
bilmez, dolayısıyla birim testleri simülatörsüz koşar.

## 4. Arama indeksi

İndeks **bellek-içidir** ve her açılışta SwiftData'dan kurulur (`HybridIndex.warmUp`).

```
BM25Index
├── postings        [term → (documentID → tf)]
├── documentLengths [documentID → token sayısı]
└── documentTerms   [documentID → terimler]   (silmeyi sözlük boyutundan bağımsız kılar)

documents           [assetIdentifier → IndexedDocument]
└── IndexedDocument { createdAt, category, amounts, title, summary, tags, embedding }
```

**Neden diske ikili biçim yazılmıyor:** 5.000 belge için sözlük ~4 MB, vektörler ~10 MB
tutar; bu modern bir iPhone'da sorun değil ve kuruluş ~1 sn sürer. Özel bir dosya biçimi
yazmak, onu sürümlemek ve göç ettirmek ancak kitaplık on binlere çıkınca kazanç sağlar.
Kaynak veri SwiftData'da durduğu için indeks her zaman kayıpsız yeniden kurulabilir —
bu, "indeks biçimi göçü" diye bir sorunu tamamen ortadan kaldırır.

Vektörler **tam OCR metninden değil**, başlık + özet + etiketlerden üretilir: ekran
görüntüsü metni arayüz gürültüsüyle ("Geri", "Paylaş", saat, pil) doludur ve cümle
vektörü bu gürültüde anlamı kaybeder. Ham metin zaten BM25 tarafında kapsanır.

## 5. Migration politikası

- **SwiftData şeması**: `VersionedSchema` + `SchemaMigrationPlan`, hafif migration tercih edilir.
- **Analiz şeması** (`AnalysisSchemaVersion`): artınca kayıtlar silinmez; `status` değişmez ama
  `schemaVersion < current` olanlar düşük öncelikli yeniden analiz kuyruğuna alınır.
- **Arama indeksi**: bellek-içi olduğu için göç gerektirmez; her açılışta yeniden kurulur.

## 6. Silme semantiği

| Eylem | Sonuç |
|---|---|
| Uygulamadan "kaldır" | `ShotRecord` silinir, **Photos'taki görsel durur** |
| Temizlik asistanından "sil" | `PHPhotoLibrary` üzerinden silme istenir → sistem onay diyaloğu → çöp kutusuna gider |
| "İndeksi sıfırla" | Tüm `ShotRecord` + index.bin silinir, görsellere dokunulmaz |
| Photos'tan silinmiş asset | Senkronizasyonda `.orphaned` → sessizce temizlenir |
