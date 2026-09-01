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
    func fullScreenPresentation(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> some View
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

    /// Izgaradaki karttan detaya büyüyen geçiş (yalnız iOS).
    ///
    /// macOS'ta `NavigationTransition.zoom` kullanılamaz; orada varsayılan geçiş kalır.
    /// Geçişin kendisi ürün için önemli ama macOS yalnız test hedefi olduğundan kayıp yok.
    func zoomTransition(sourceID: some Hashable, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        #else
        self
        #endif
    }

    /// Arama çubuğunu her zaman görünür tutar (yalnız iOS'ta yerleşim seçilebilir).
    func alwaysVisibleSearchBar(
        text: Binding<String>,
        prompt: some StringProtocol
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
