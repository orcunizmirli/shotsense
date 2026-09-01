# ShotSense

**On-device screenshot & document intelligence for iOS 26.**

Telefonundaki ekran görüntüsü yığınını — hiçbiri cihazdan çıkmadan — sınıflandıran,
aranabilir yapan ve aksiyona çeviren SwiftUI uygulaması.

- **Vision** (`RecognizeDocumentsRequest`) ile yapısal OCR
- **Foundation Models** ile şemalı sınıflandırma, özet ve varlık çıkarımı (`@Generable`)
- Hibrit arama: BM25 + `NLEmbedding` cümle vektörleri + doğal dil sorgu ayrıştırma
- Tek dokunuşla Hatırlatıcı / Takvim / kopyala
- **Sunucu yok, ağ isteği yok, hesap yok.** Değişken maliyet sıfır.

## Belgeler

| | |
|---|---|
| [00 — Genel Bakış](docs/00-genel-bakis.md) | Problem, çözüm, iş modeli, riskler |
| [01 — Özellik Envanteri](docs/01-ozellik-envanteri.md) | P0/P1/P2 kapsam |
| [02 — Ekran Haritası](docs/02-ekran-haritasi.md) | Navigasyon, ekranlar, durum matrisi |
| [03 — Mimari](docs/03-mimari.md) | Paket grafiği, bağımlılık kuralları, eşzamanlılık |
| [04 — Zekâ Pipeline'ı](docs/04-zeka-pipeline.md) | OCR → analiz → doğrulama → indeks |
| [05 — Veri Modeli](docs/05-veri-modeli.md) | SwiftData şeması, indeks formatı, migration |
| [06 — Monetizasyon](docs/06-monetizasyon.md) | StoreKit 2, limitler, birim ekonomi |
| [07 — Gizlilik](docs/07-gizlilik.md) | İzinler, App Review, hassas veri |
| [08 — Yol Haritası](docs/08-yol-haritasi.md) | M0–M6, task listesi, çıkış kriterleri |
| [KANON](docs/KANON.md) | Değişmez kurallar |

## Durum

| Milestone | Kapsam | Durum |
|---|---|---|
| M0 | Repo iskeleti, AppFoundation, ShotCore, mimari denetçisi, CI | ✅ |
| M1 | OCRKit (Vision), IntelligenceKit (Foundation Models + heuristik) | ✅ |
| M2 | IngestKit (Photos), IndexKit (SwiftData), AnalysisPipeline | ✅ |
| M3 | BM25 + NLEmbedding hibrit arama, sorgu ayrıştırma | ✅ |
| M4 | DesignSystem, LibraryKit (kitaplık / arama / detay / ayarlar / paywall) | ✅ |
| M5 | ActionKit (EventKit), PaywallKit (StoreKit 2), kota sayacı | ✅ |
| M6 | Onboarding, arka plan indeksleme, kompozisyon kökü | ✅ |

> **Not:** kod bu depoda Xcode olmadan yazıldı; ilk `xcodegen generate && xcodebuild` turunda
> derleyici uyarlaması gerekebilir. En yeni API yüzeyi olan Vision belge-konteyner eşlemesi
> bu yüzden tek dosyada (`Packages/OCRKit/Sources/OCRKit/VisionDocumentMapper.swift`)
> izole edilmiştir; o yol tamamen başarısız olsa bile OCR metin ve barkod üretmeye devam eder.

## Mimari özeti

```
AppFoundation ──▶ ShotCore (domain + portlar) ──▶ adaptörler (OCR/Intelligence/Ingest/
                        │                          Index/Action/Paywall)
                        └──▶ DesignSystem ──▶ LibraryKit (arayüz)
                                                   │
                                            ShotSenseApp (kompozisyon kökü)
```

Kurallar CI'da zorlanır (`Scripts/dependency-lint.swift`): domain saf kalır, adaptörler
birbirini görmez, arayüz adaptör bilmez, hiçbir yerde ağ API'si veya UIKit yoktur.

## Geliştirme

Gereksinimler: **Xcode 26+**, iOS 26 SDK, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen swiftlint
xcodegen generate          # ShotSense.xcodeproj üretir
open ShotSense.xcodeproj
```

Paketleri tek başına test etmek için:

```bash
cd Packages/ShotCore && swift test      # tüm paketler simülatörsüz koşar (macOS 26 hedefli)
```

Bağımlılık kurallarını denetlemek için:

```bash
swift Scripts/dependency-lint.swift
```
