# 02 — Ekran Haritası ve Navigasyon

## 1. Navigasyon iskeleti

`TabView` (3 sekme) + tam ekran modaller. Portrait-locked (v1).

```
RootView
├── Tab "Kitaplık"    → LibraryView ──▶ ShotDetailView ──▶ ActionSheet(Hatırlatıcı/Takvim)
│                                   └─▶ ImageViewerView (zoom)
├── Tab "Ara"         → SearchView ───▶ ShotDetailView
└── Tab "Ayarlar"     → SettingsView ─▶ IndexingSettingsView
                                     ├▶ PrivacyView
                                     └▶ SubscriptionView
Modaller:
  OnboardingFlow  (ilk açılış)
  PaywallView     (limit aşımı / Pro özellik dokunuşu)
  CleanupView     (temizlik asistanı, P1)
```

## 2. Ekran ekran

### 2.1 OnboardingFlow (modal, 4 adım)
1. **Değer** — "4.000 screenshot'ın var. Hiçbiri telefonundan çıkmadan aranabilir olsun."
2. **Örnek** — `PHPicker` ile kullanıcı 3 screenshot seçer, canlı analiz gösterilir (**izin istemeden**).
3. **İzin** — sonuç görüldükten sonra tam Photos erişimi istenir. Reddedilirse ürün sınırlı modda çalışır.
4. **İndeksleme** — ilerleme çubuğu; arka planda devam edebilir, kullanıcı beklemez.

> Kanon: izin ekranı **asla ilk ekran değildir**. Önce değer, sonra izin.

### 2.2 LibraryView
- Üstte: yatay kategori çipleri (Tümü, Fiş, Bilet, Wifi, …) + sayaç.
- Gövde: `LazyVGrid` 3 sütun, thumbnail + kategori rozeti + tarih.
- Analiz sürüyorsa üstte ince ilerleme bandı ("1.240 / 4.012 analiz edildi").
- Boş durumlar: izin yok / screenshot yok / kategori boş — üçü ayrı metin.
- Sağ üst: seçim modu (çoklu → sil / koleksiyona ekle).

### 2.3 SearchView
- Arama alanı + "Doğal dilde sor" ipucu.
- Sorgu yazılırken: anlık BM25 sonuçları (yerel, senkron).
- Enter / 400 ms duraklama: LLM sorgu ayrıştırma + hibrit sıralama → sonuç listesi.
- Ayrıştırılan filtreler **görünür çip** olarak gösterilir ("kategori: fiş", "tarih: son 30 gün")
  ve tek dokunuşla kaldırılabilir → kullanıcı LLM'in ne anladığını görür (güven).
- Öneri satırları: son aramalar + "Yaklaşan tarihler" + "Wifi şifreleri".

### 2.4 ShotDetailView
- Üstte görsel (dokun → `ImageViewerView`).
- Başlık (LLM), kategori rozeti, tarih.
- **Özet** kartı (1–2 cümle).
- **Çıkarılan bilgiler** listesi: her satır bir varlık; sağında kopyala / aksiyon düğmesi.
  - Tarih satırı → "Hatırlatıcı kur", "Takvime ekle"
  - Tutar/satıcı → "Kopyala"
  - Wifi → "Şifreyi kopyala"
  - URL → "Aç"
- **Metin** bölümü (katlanabilir, tam OCR çıktısı, seçilebilir).
- Alt bar: Paylaş · Koleksiyona ekle · Sil · "Yanlış mı? Düzelt".

### 2.5 SettingsView
- Abonelik durumu (Free/Pro, yönet).
- İndeksleme: otomatik/manuel, yalnız şarjda, "Şimdi yeniden analiz et".
- Dil (OCR dilleri).
- Gizlilik: "Bu uygulama ağ isteği yapmaz" + `07-gizlilik.md` özeti.
- Veri: indeksi sıfırla (görseller silinmez), dışa aktar.
- Zekâ durumu: "Apple Intelligence: açık / bu cihazda desteklenmiyor (heuristik mod)".

### 2.6 PaywallView
Tetikleyiciler: (a) 200. screenshot sonrası kitaplık, (b) 11. arama, (c) 4. aksiyon,
(d) Pro özellik dokunuşu. Ayda **en fazla 3 kez** otomatik gösterilir (kanon).

## 3. Durum matrisi (her liste ekranı için zorunlu)

| Durum | Gösterim |
|---|---|
| İzin yok | Açıklama + "Ayarlar'ı aç" + "Elle ekle" |
| İzin var, veri yok | "Ekran görüntüsü bulunamadı" |
| İndeksleme sürüyor, sonuç yok | İskelet (skeleton) hücreler |
| Sonuç var | İçerik |
| Hata | Kısa neden + "Tekrar dene" |

## 4. Akıcılık kuralları (premium his)

Premium algı iki şeyden doğar: **hiç takılmama** ve **tutarlı hareket**. İkisi de
mimariyle korunur, "sonra iyileştiririz" ile değil.

### 4.1 Kaydırma bütçesi

| Kural | Gerekçe |
|---|---|
| Önizlemeler **toplu** okunur (`ShotIndexing.thumbnails(for:)`) | Hücre başına ayrı okuma, veri deposu aktörüne görünen hücre kadar gidiş-dönüş demektir; hepsi sıraya girer |
| Çözme **arka planda ve görüntüleme boyutunda** | 1290×2796 bir görsel tam boyutta 14 MB bitmap üretir; 30 hücre 400 MB'ı aşar |
| İstekler 30 ms'lik pencerede toplanır | Bir kaydırma darbesi onlarca hücre açar; hepsi tek partiye iner |
| 15 hücre ileriye **ön yükleme** | Kullanıcı oraya varmadan görsel hazırdır; boş kare görülmez |
| LRU tavanı 150 görsel (~35 MB) | Sınırsız önbellek arka plandaki uygulamayı sonlandırır |
| `View.body` içinden çağrılan fonksiyonlar **yan etkisiz** | İş başlatan bir okuma, her yeniden çizimde yeni görev doğurur |
| Kategori çipleri **tek sorgu** | Kategori başına sorgu 14 gidiş-dönüş eder ve her yenilemede tekrarlanır |
| İndeksleme sırasında ızgara **en fazla 2 sn'de bir** tazelenir | Her partide yenilemek ızgarayı saniyede birkaç kez baştan kurar |
| Aramada 140 ms debounce | Hızlı yazan kullanıcıda saniyede 8-10 arama, her biri listeyi baştan kurar |
| Hücreler **sabit oranlı** (9:16) | Değişken yükseklik `LazyVGrid`'i her yüklemede yeniden ölçmeye zorlar |
| Gölgeler `compositingGroup` sonrası | Aksi hâlde her alt katman için ayrı hesaplanır |

### 4.2 Hareket

- Tüm animasyonlar **yay** tabanlıdır (`Token.Motion`), süre tabanlı değil: kesintiye
  uğradığında hızını koruyarak yeni hedefe yönelir, zıplamaz.
- Izgaradan detaya **zoom geçişi** (`.navigationTransition(.zoom)`): kullanıcı hangi
  öğeye girdiğini ve geri dönüş yönünü kaybetmez.
- Seçim vurgusu çipler arasında **kayar** (`matchedGeometryEffect`), anlık değişmez.
- Sayılar `contentTransition(.numericText())` ile geçer.
- Her dokunulabilir yüzey basıldığında küçülür (`PressableButtonStyle`); yanıt vermeyen
  yüzey "dokunma algılanmadı" hissi verir.
- **Hareketi Azalt** açıkken tüm bunlar kapanır (`Token.Motion.respectingReduceMotion`);
  parıltı gibi sürekli tekrarlı efektler hiç başlamaz.
- Haptik geri bildirim `.sensoryFeedback` ile verilir (UIKit gerektirmez, R6).

### 4.3 Yükleme

- Boş ekran yerine **iskelet + parıltı**; ızgara yüksekliği baştan doğru.
- Detayda **aşamalı yükleme**: önce önizleme, sonra tam görsel.
- Görseller belirerek gelir, "pop" yapmaz.

## 5. Erişilebilirlik kuralları
- Tüm dokunma hedefleri ≥ 44×44 pt.
- Her thumbnail'in `accessibilityLabel`'ı = LLM başlığı + kategori + tarih.
- Dynamic Type XXL'de grid 3→2→1 sütuna düşer.
- Renk **tek başına** kategori taşıyıcısı değildir; her rozette ikon + metin vardır.
