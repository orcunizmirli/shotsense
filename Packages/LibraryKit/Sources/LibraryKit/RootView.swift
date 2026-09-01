import DesignSystem
import ShotCore
import SwiftUI

/// Uygulamanın sekme iskeleti (02 §1).
public struct RootView: View {
    private let dependencies: LibraryDependencies
    @State private var paywall = PaywallPresenter()
    @State private var librarySelection = NavigationPath()
    @State private var searchSelection = NavigationPath()

    public init(dependencies: LibraryDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        TabView {
            Tab("Kitaplık", systemImage: "square.grid.2x2") {
                NavigationStack(path: $librarySelection) {
                    LibraryView(dependencies: dependencies, paywall: paywall)
                }
            }
            Tab("Ara", systemImage: "magnifyingglass", role: .search) {
                NavigationStack(path: $searchSelection) {
                    SearchView(dependencies: dependencies, paywall: paywall)
                }
            }
            Tab("Ayarlar", systemImage: "gearshape") {
                NavigationStack {
                    SettingsView(dependencies: dependencies, paywall: paywall)
                }
            }
        }
        .sheet(isPresented: $paywall.isPresented) {
            PaywallView(dependencies: dependencies, trigger: paywall.trigger ?? .settings)
                // Paywall tam ekran değil sayfa olarak açılır: kullanıcı arkasındaki
                // içeriği görmeye devam eder ve "kapana kısıldım" hissi oluşmaz.
                .largeSheetPresentation()
        }
    }
}
