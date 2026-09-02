# 09 — TestFlight Otomatik Dağıtımı

`.github/workflows/testflight.yml` bir sürüm etiketiyle (veya Actions sekmesinden elle)
çalışır; imzalar, arşivler ve build'i App Store Connect'e yükler. Aşağıdaki kurulum
**bir kez** yapılır.

## 1. Ne otomatik, ne değil

| Adım | Otomatik mi |
|---|---|
| Derleme, imzalama, arşivleme | ✅ |
| Build numarası artırma | ✅ (iş akışı sayacı) |
| App Store Connect'e yükleme | ✅ |
| Dışa aktarım uyumluluğu sorusu | ✅ (`ITSAppUsesNonExemptEncryption: false`) |
| **İç** test kullanıcılarına dağıtım | ✅ (build işlenince, ~5–15 dk) |
| **Dış** test kullanıcılarına dağıtım | ⚠️ İlk build Beta App Review'dan geçer (genelde <24 sa); sonrakiler çoğunlukla otomatik |
| App Store'a yayın (satış) | ❌ Ayrı bir karar, ayrı bir inceleme |

## 2. Apple tarafı kurulum

**2.1 Bundle ID.** [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list)
→ Identifiers → yeni App ID: `com.shotsense.app`. Yetenek (capability) işaretlemeye
gerek yok — uygulama Push, iCloud, App Groups kullanmıyor. Arka plan görevi ve EventKit
yetenek istemez, Info.plist yeterlidir.

**2.2 Uygulama kaydı.** App Store Connect → Apps → **+** → iOS, bundle ID'yi seç, SKU
serbest (ör. `shotsense-ios`). Uygulama kaydı olmadan yükleme reddedilir.

**2.3 API anahtarı.** App Store Connect → Users and Access → Integrations →
App Store Connect API → **Team Keys** → **+**. Rol: **App Manager**.
- `.p8` dosyası **yalnız bir kez** indirilir, kaybolursa yenisini üretmen gerekir.
- Sayfada görünen **Key ID** ve **Issuer ID**'yi not al.

Neden API anahtarı: Apple ID + parola ile yükleme iki adımlı doğrulamaya takılır ve CI'da
çalışmaz.

**2.4 Dağıtım sertifikası.** Bir Mac'te Xcode → Settings → Accounts → hesabını seç →
Manage Certificates → **+** → **Apple Distribution**. Sonra Keychain Access'te bu
sertifikayı bul, **özel anahtarıyla birlikte** sağ tık → Export → `.p12`, bir parola ver.

> Provisioning profile'ı elle indirmene gerek yok: iş akışı `-allowProvisioningUpdates`
> ile API anahtarını kullanıp App Store profilini kendisi üretir/indirir.

**2.5 Team ID.** developer.apple.com → Membership → Team ID (10 karakter).

## 3. GitHub secret'ları

Repo → Settings → Secrets and variables → Actions → New repository secret.

| Secret | Nasıl elde edilir |
|---|---|
| `APPLE_TEAM_ID` | 2.5'teki 10 karakter |
| `ASC_KEY_ID` | 2.3'teki Key ID |
| `ASC_ISSUER_ID` | 2.3'teki Issuer ID |
| `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `DIST_CERT_P12_BASE64` | `base64 -i dist.p12 \| pbcopy` |
| `DIST_CERT_PASSWORD` | 2.4'te verdiğin `.p12` parolası |

Base64'e çevirmenin sebebi: secret'lar tek satır metindir, ikili dosya doğrudan
saklanamaz. macOS'ta `base64 -i` satır sonu üretmez; Linux'ta `base64 -w0` kullan.

İş akışı ilk adımda eksik secret'ı bildirip durur — 40 dakikalık derlemenin sonunda
öğrenmemek için.

## 4. Çalıştırma

```bash
git tag v1.0.0 && git push origin v1.0.0
```

veya Actions → **TestFlight** → Run workflow (istersen build numarasını elle verirsin).

Her push'ta yüklemek istersen `testflight.yml` içindeki `on:` bloğuna
`branches: [main]` ekle. Öntanımlı olarak kapalı, çünkü her yükleme bir build numarası
harcar ve tüm iç test kullanıcılarına bildirim gider.

## 5. TestFlight tarafı

- **İç test (internal):** ekibindeki App Store Connect kullanıcıları, en fazla 100 kişi.
  İnceleme yok. Build "Processing"i bitirince dağıtılır.
- **Dış test (external):** 10.000 kişiye kadar, e-posta veya genel davet bağlantısıyla.
  İlk build Beta App Review'dan geçer.
- **Her build'i otomatik dağıtmak için:** TestFlight → grubu seç → *Automatically
  distribute builds to testers*. Bu açık değilse build yüklenir ama kimseye gitmez;
  "neden test kullanıcılarına ulaşmadı" sorusunun en sık cevabı budur.
- Build'ler **90 gün** sonra dolar.

Dış test için ayrıca gizlilik politikası bağlantısı, beta açıklaması ve iletişim
bilgisi istenir (07-gizlilik.md metinleri buraya doğrudan kullanılabilir).

## 6. Sürüm ve build numarası

- **Sürüm** (`MARKETING_VERSION`) `project.yml`'da: 1.0.0.
- **Build numarası** (`CURRENT_PROJECT_VERSION`) iş akışı sayacından gelir.

Kural: aynı sürüm için build numarası **her zaman artmalı**. Sayaç sıfırlanırsa veya bir
çakışma olursa `workflow_dispatch` ile daha büyük bir sayı ver.

## 7. Sık çıkan hatalar

| Hata | Sebep |
|---|---|
| `No profiles for 'com.shotsense.app' were found` | Bundle ID kayıtlı değil ya da API anahtarının rolü App Manager değil |
| `Missing app icon` / `CFBundleIconName` | `App/Assets.xcassets` build'e girmemiş |
| `The provided entity includes an attribute with a value that has already been used` | Build numarası tekrar etti |
| `Invalid Signature` / `unknown authority` | Anahtarlık arama listesi sistem anahtarlığını düşürdü (iş akışı bunu koruyacak şekilde yazıldı) |
| Build "Processing"de takılı | Genelde 10–30 dk; 1 saati aşarsa ikon/plist doğrulaması düşmüştür, e-posta gelir |

## 8. Maliyet

macOS runner'ları **private** depolarda dakika kotasını 10 katı hızla tüketir. Bu iş
akışının bir koşusu ~15–25 dakika ⇒ ~150–250 dakika kota. Sık yükleme yapacaksan
alternatif **Xcode Cloud**: ayda 25 saat ücretsiz, sertifika/secret kurulumu gerekmez
(Apple imzalamayı kendi yönetir), ama Apple'ın altyapısına bağlanırsın. Bu depodaki CI
zaten GitHub Actions'ta olduğu için burada onu kullandık.

## 9. Bundan sonra hâlâ elle yapılması gerekenler

- App Store ekran görüntüleri ve metinleri (SS-062).
- Sandbox'ta satın alma/iptal/geri yükleme doğrulaması (06 §7) — StoreKit sandbox
  gerçek bir cihaz ve test hesabı ister.
- 5.000 görsellik kitaplıkta ilk indeksleme ölçümü (SS-061) — gerçek cihaz gerektirir.
- **Uygulama ikonu şu an yer tutucudur** (`App/Assets.xcassets`): programatik üretilmiş
  bir belge+mercek işareti. TestFlight'ı geçmeye yeter; App Store'a çıkmadan önce
  tasarlanmış bir ikonla değiştir.
