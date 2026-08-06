#if !os(tvOS)
import SwiftUI

// MARK: - Footer-Bar bei Verbindungsfehler (einheitlich für Katalog- und Detail-Listen)

/// Eingaben für die gemeinsame Regel: Floating-Bar aus, wenn kein Server aktiv ist oder die aktuelle Liste leer ist
/// und ein Fehler angezeigt wird (typisch `ConnectionErrorView`).
struct CatalogFloatingChromeState: Equatable {
    var hasActiveServerConfig: Bool
    var primaryListIsEmpty: Bool
    var errorMessage: String?
    var imageFindListError: String? = nil

    /// `isPresented`: z. B. `showsFloatingFilterButton` — wird zusätzlich zur Fehlerlogik ausgewertet.
    func floatingBarVisible(isPresented: Bool) -> Bool {
        guard isPresented else { return false }
        guard hasActiveServerConfig else { return false }
        if primaryListIsEmpty, errorMessage != nil || imageFindListError != nil {
            return false
        }
        return true
    }
}

struct FloatingActionBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(.system(size: 17))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, DesignTokens.Chrome.fabInnerPadding)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .floatingShadow()
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(DesignTokens.Chrome.strokeOpacity), lineWidth: 0.5)
            )
            .frame(height: DesignTokens.Chrome.fabHeight)
            .padding(.horizontal, DesignTokens.Chrome.fabOuterPadding)
            .padding(.bottom, DesignTokens.Chrome.fabBottomPadding)
    }
}

extension View {
    /// Floating-Bar über `safeAreaInset`. Mit `catalogChrome` wird sie bei fehlendem Server / leerer Liste + Fehler ausgeblendet.
    func floatingActionBar<Content: View>(
        isPresented: Bool = true,
        catalogChrome: CatalogFloatingChromeState? = nil,
        @ViewBuilder _ content: @escaping () -> Content
    ) -> some View {
        let showBar = catalogChrome?.floatingBarVisible(isPresented: isPresented) ?? isPresented
        return Group {
            if showBar {
                self.safeAreaInset(edge: .bottom, spacing: 0) {
                    FloatingActionBar(content: content)
                }
            } else {
                self
            }
        }
    }

    /// Kurzform ohne Fehler-Logik (z. B. rein dekorative Bars).
    func floatingActionBar<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        floatingActionBar(isPresented: true, catalogChrome: nil, content)
    }
}

// MARK: - Category row (expanding dock icons / pills)

struct CatalogCategoryRow: View {
    let tabs: [CatalogsView.CatalogsTab]
    @Binding var selection: CatalogsView.CatalogsTab

    var body: some View {
        StashyTopNavNameDropdownRow(
            title: "Home",
            items: tabs.map { StashyNavMenuItem(id: $0.rawValue, title: $0.rawValue, systemImage: $0.icon) },
            selectionID: selection.rawValue,
            titleColor: .white,
            menuAccessibilityLabel: "Catalog",
            menuAccessibilityHint: "Chooses which catalog section to show"
        ) { id in
            if let tab = CatalogsView.CatalogsTab(rawValue: id) {
                selection = tab
            }
        }
    }
}

struct SettingsCategoryRow: View {
    @Binding var selection: SettingsView.SettingsSection

    var body: some View {
        StashyTopNavNameDropdownRow(
            title: "Settings",
            items: SettingsView.SettingsSection.allCases.map {
                StashyNavMenuItem(id: $0.rawValue, title: $0.rawValue, systemImage: $0.icon)
            },
            selectionID: selection.rawValue,
            titleColor: .white,
            menuAccessibilityLabel: "Settings section",
            menuAccessibilityHint: "Chooses which settings section to show"
        ) { id in
            if let section = SettingsView.SettingsSection(rawValue: id) {
                selection = section
            }
        }
    }
}
#endif
