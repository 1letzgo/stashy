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
            // Same Liquid Glass as the rest of the chrome (material + hairline before iOS 26).
            .stashyGlass(shape: Capsule())
            .floatingShadow()
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
        // Immer dieselbe Struktur: nur die Bar ist bedingt, nicht der `safeAreaInset`.
        // Ein `if showBar { self.safeAreaInset… } else { self }` wechselt den View-Zweig
        // und reißt damit alles unter `self` ab — inklusive gepushter Detailseiten
        // (`navigationDestination` / `NavigationLink`), die dann sofort neu gepusht
        // werden: Endlosschleife aus Laden und Verschwinden bei leeren Listen.
        return self.safeAreaInset(edge: .bottom, spacing: 0) {
            if showBar {
                FloatingActionBar(content: content)
            }
        }
    }

    /// Kurzform ohne Fehler-Logik (z. B. rein dekorative Bars).
    func floatingActionBar<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        floatingActionBar(isPresented: true, catalogChrome: nil, content)
    }
}

// MARK: - Home breadcrumb (Home · Library › sort)

/// Middle crumb of the Home chrome: a native menu with every library view (not the dashboard,
/// that is the Home button), labelled with the icon of the one shown. The list's own controls
/// (sort menu, filter button) follow it in the same row.
struct HomeViewsMenu: View {
    let tabs: [CatalogsView.CatalogsTab]
    @Binding var selection: CatalogsView.CatalogsTab
    @ObservedObject private var appearance = AppearanceManager.shared

    /// Every view except the dashboard, in the user's order.
    var libraryTabs: [CatalogsView.CatalogsTab] { tabs.filter { $0 != .dashboard } }

    var body: some View {
        Menu {
            Picker("Library", selection: $selection) {
                ForEach(libraryTabs, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Text(selection.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            // Always highlighted: it names the view that is shown (the sort crumb is too).
            .foregroundStyle(Color.onAppTint)
            .padding(.horizontal, StashyExpandingDock.activeHorizontalPadding)
            .frame(height: StashyExpandingDock.activeHeight)
            .stashyChromeFill(shape: Capsule(style: .continuous), activeColor: appearance.tintColor)
            .contentShape(Capsule(style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Library, \(selection.rawValue)")
    }
}

/// One row of breadcrumb chrome. On the dashboard: Home (highlighted) › every library view as
/// an icon. In a view: Home › views menu, and at the right edge whatever the list puts there
/// (sort menu, settings).
struct HomeBreadcrumbRow<Trailing: View>: View {
    let menu: HomeViewsMenu
    @ViewBuilder var trailing: () -> Trailing

    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        let onHome = menu.selection == .dashboard
        HStack(spacing: 6) {
            // Without a visible dashboard (switched off in Settings › Home Tabs) there is no Home.
            if menu.tabs.contains(.dashboard) {
                homeButton(onHome: onHome)
                separator
            }
            if onHome {
                StashyExpandingDockBrowseStrip(
                    items: menu.libraryTabs.map {
                        StashyNavMenuItem(id: $0.rawValue, title: $0.rawValue, systemImage: $0.icon)
                    },
                    selectionID: "",
                    accessibilityLabel: "Library",
                    accessibilityHint: "Opens a library view"
                ) { id in
                    if let tab = CatalogsView.CatalogsTab(rawValue: id) {
                        menu.selection = tab
                    }
                }
            } else {
                menu
                // The list's controls (sort menu, settings) sit at the right edge, not as a crumb.
                Spacer(minLength: 0)
                trailing()
            }
        }
        .padding(.bottom, 4)
    }

    private func homeButton(onHome: Bool) -> some View {
        Button {
            guard !onHome else { return }
            HapticManager.light()
            menu.selection = .dashboard
        } label: {
            Image(systemName: "house.fill")
                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                .foregroundStyle(onHome ? Color.onAppTint : Color.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                .frame(width: StashyExpandingDock.circleSize, height: StashyExpandingDock.circleSize)
                .stashyChromeFill(shape: Circle(), activeColor: onHome ? appearance.tintColor : nil)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Home")
        .accessibilityAddTraits(onHome ? .isSelected : [])
    }

    private var separator: some View {
        Image(systemName: "chevron.compact.right")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.4))
            .accessibilityHidden(true)
    }
}

/// The Home views menu, set by `CatalogsView` for the list it shows. A list reads it to draw
/// the breadcrumb itself (Home › view › its sort) and clears it for everything below, so a
/// list embedded in a pushed detail page never draws one.
private struct HomeBreadcrumbMenuKey: EnvironmentKey {
    static let defaultValue: HomeViewsMenu? = nil
}

extension EnvironmentValues {
    var homeBreadcrumbMenu: HomeViewsMenu? {
        get { self[HomeBreadcrumbMenuKey.self] }
        set { self[HomeBreadcrumbMenuKey.self] = newValue }
    }
}

extension View {
    /// Home breadcrumb chrome for a catalog list: Home › views menu › the list's sort menu.
    /// No-op (apart from clearing the menu for descendants) when `menu` is nil.
    func homeBreadcrumbChrome<Sort: View>(
        _ menu: HomeViewsMenu?,
        showsSort: Bool = true,
        @ViewBuilder sort: @escaping () -> Sort
    ) -> some View {
        environment(\.homeBreadcrumbMenu, nil)
            .stashySectionChrome(showsSwitcher: menu != nil) {
                if let menu {
                    if showsSort {
                        HomeBreadcrumbRow(menu: menu) { sort() }
                    } else {
                        HomeBreadcrumbRow(menu: menu) { EmptyView() }
                    }
                }
            }
    }
}

struct SettingsCategoryRow: View {
    @Binding var selection: SettingsView.SettingsSection
    var sections: [SettingsView.SettingsSection] = Array(SettingsView.SettingsSection.allCases)

    var body: some View {
        StashyTopNavNameDropdownRow(
            title: sections.count == 1 ? (sections.first?.rawValue ?? "Settings") : "Settings",
            items: sections.map {
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
