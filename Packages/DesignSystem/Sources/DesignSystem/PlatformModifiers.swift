import SwiftUI

/// iOS'a özel görünüm değiştiricilerinin platformdan bağımsız sarmalayıcıları.
///
/// **Neden gerekli:** arayüz paketleri macOS'u da hedefler — böylece görünüm modeli
/// testleri simülatör başlatmadan, saniyeler içinde koşar (03 §8). Ama `SwiftUI`'nin bir
/// bölümü yalnız iOS'ta vardır (`navigationBarTitleDisplayMode`, `fullScreenCover`,
/// `presentationDetents`, arama çubuğu yerleşimi). Bu farkı her çağrı yerine `#if` serpmek
/// yerine tek dosyada kapatmak, ekran kodunu okunur tutar ve bir platform daha eklenirse
/// değişiklik tek yerde kalır.
public extension View {
    /// iOS'ta satır içi başlık; macOS'ta karşılığı yoktur.
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// iOS'ta tam ekran örtü, macOS'ta sayfa.
    ///
    /// Tam ekran inceleyici gibi ekranlar iOS'ta örtü olarak açılmalıdır; macOS'ta
    /// böyle bir sunum tarzı yoktur ve sayfa doğru karşılıktır.
    func fullScreenPresentation<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }

    /// Sayfanın tam yükseklikte, sürükleme göstergesiyle açılması (yalnız iOS).
    func largeSheetPresentation() -> some View {
        #if os(iOS)
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
        #else
        self
        #endif
    }

    /// Arama çubuğunu her zaman görünür tutar (yalnız iOS'ta yerleşim seçilebilir).
    func alwaysVisibleSearchBar<S: StringProtocol>(
        text: Binding<String>,
        prompt: S
    ) -> some View {
        #if os(iOS)
        searchable(
            text: text,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(prompt)
        )
        #else
        searchable(text: text, prompt: Text(prompt))
        #endif
    }
}
