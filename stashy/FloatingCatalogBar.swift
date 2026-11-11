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
extension View {
    /// Menu items in the label colour instead of the accent: on clear Liquid Glass over busy
    /// covers a coloured icon or checkmark (a bright purple accent, say) makes the rows hard to
    /// read. The pill that opens the menu sets its own colours, so it keeps the accent.
    func stashyNeutralMenuItems() -> some View {
        tint(.primary)
    }
}

struct HomeViewsMenu: View {
    let tabs: [CatalogsView.CatalogsTab]
    @Binding var selection: CatalogsView.CatalogsTab
    @ObservedObject private var appearance = AppearanceManager.shared

    /// Every view except the dashboard, in the user's order.
    var libraryTabs: [CatalogsView.CatalogsTab] { tabs.filter { $0 != .dashboard } }

    /// On the dashboard no library view is open: the pill reads "Dashboard" in plain glass (Home
    /// beside it is the highlighted one) and the entries are plain buttons, no checkmark.
    private var onDashboard: Bool { selection == .dashboard }

    var body: some View {
        Menu {
            if onDashboard {
                ForEach(libraryTabs, id: \.self) { tab in
                    Button {
                        selection = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
                    }
                }
            } else {
                Picker(tr("library"), selection: $selection) {
                    ForEach(libraryTabs, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            HStack(spacing: 6) {
                Text(onDashboard ? tr("dashboard") : selection.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            // Highlighted while it names the view that is shown (the sort crumb is too).
            .foregroundStyle(onDashboard ? Color.white.opacity(0.85) : Color.onAppTint)
            .padding(.horizontal, StashyExpandingDock.activeHorizontalPadding)
            .frame(height: StashyExpandingDock.activeHeight)
            .stashyChromeFill(shape: Capsule(style: .continuous), activeColor: onDashboard ? nil : appearance.tintColor)
            .contentShape(Capsule(style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .stashyNeutralMenuItems()
        .fixedSize()
        .accessibilityLabel(onDashboard ? tr("dashboard") : "Library, \(selection.rawValue)")
    }
}

/// A detail page's sections (a performer's Scenes, Galleries, Images, …) for the breadcrumb row:
/// Back, then a dropdown naming the shown section, like `HomeViewsMenu` in the overviews.
struct DetailBreadcrumb {
    struct Section: Identifiable, Hashable {
        let id: String
        let title: String
        let systemImage: String
    }

    let sections: [Section]
    let selectionID: String
    let onSelect: (String) -> Void
    let onBack: () -> Void

    var selectedTitle: String {
        sections.first { $0.id == selectionID }?.title ?? sections.first?.title ?? ""
    }
}

private struct DetailBreadcrumbKey: EnvironmentKey {
    static let defaultValue: DetailBreadcrumb? = nil
}

extension EnvironmentValues {
    /// Set by a detail page for the list it shows: the list draws Back · section menu with its
    /// own sort menu and settings at the right edge (`detailBreadcrumbChrome`).
    var detailBreadcrumb: DetailBreadcrumb? {
        get { self[DetailBreadcrumbKey.self] }
        set { self[DetailBreadcrumbKey.self] = newValue }
    }
}

/// Back · section dropdown, and the shown list's controls at the right edge.
struct DetailBreadcrumbRow<Trailing: View>: View {
    let crumb: DetailBreadcrumb
    @ViewBuilder var trailing: () -> Trailing

    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        HStack(spacing: 6) {
            Button {
                HapticManager.light()
                crumb.onBack()
            } label: {
                // Like the overviews' Home button: plain glass; the section menu is the highlight.
                Image(systemName: "chevron.left")
                    .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                    .frame(width: StashyExpandingDock.circleSize, height: StashyExpandingDock.circleSize)
                    .stashyChromeFill(shape: Circle(), activeColor: nil)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("back"))
            sectionMenu
            Spacer(minLength: 0)
            trailing()
        }
        .mask(Rectangle().padding(.vertical, -24))
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var sectionMenu: some View {
        if crumb.sections.count > 1 {
            Menu {
                Picker(tr("section"), selection: Binding(
                    get: { crumb.selectionID },
                    set: { crumb.onSelect($0) }
                )) {
                    ForEach(crumb.sections) { section in
                        Label(section.title, systemImage: section.systemImage).tag(section.id)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                sectionLabel(showsChevron: true)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .stashyNeutralMenuItems()
            .fixedSize()
            .accessibilityLabel("Section, \(crumb.selectedTitle)")
        } else if !crumb.sections.isEmpty {
            sectionLabel(showsChevron: false)
                .fixedSize()
        }
    }

    private func sectionLabel(showsChevron: Bool) -> some View {
        HStack(spacing: 6) {
            Text(crumb.selectedTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
        }
        // Always highlighted, like the overviews' views menu: it names what is shown.
        .foregroundStyle(Color.onAppTint)
        .padding(.horizontal, StashyExpandingDock.activeHorizontalPadding)
        .frame(height: StashyExpandingDock.activeHeight)
        .stashyChromeFill(shape: Capsule(style: .continuous), activeColor: appearance.tintColor)
        .contentShape(Capsule(style: .continuous))
    }
}

/// One row of breadcrumb chrome. On the dashboard: Home (highlighted) › "Dashboard" dropdown
/// with every library view. In a view: Home › views menu, and at the right edge whatever the list puts there
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
                // The library views as a dropdown, like in a view; Downloads at the right edge.
                menu
                Spacer(minLength: 0)
                trailing()
            } else {
                menu
                // The list's controls (sort menu, settings) sit at the right edge, not as a crumb.
                Spacer(minLength: 0)
                trailing()
            }
        }
        // The icon strip renders its glass under a mask (its scroll view's side clip); the Home
        // button outside it kept live glass, which fades on its own curve when the chrome hides.
        // The same mask over the whole row makes every pill fade as one.
        .mask(Rectangle().padding(.vertical, -24))
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
        .accessibilityLabel(tr("home"))
        .accessibilityAddTraits(onHome ? .isSelected : [])
    }

    private var separator: some View {
        Image(systemName: "chevron.compact.right")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.4))
            .accessibilityHidden(true)
    }
}

/// A glass circle at the right of the Dashboard row, like the Home button: the watchlist
/// popup and Downloads.
struct HomeRowIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                .foregroundStyle(Color.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                .frame(width: StashyExpandingDock.circleSize, height: StashyExpandingDock.circleSize)
                .stashyChromeFill(shape: Circle(), activeColor: nil)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
    /// Detail pages: Back · section menu · the list's sort menu and settings, as the section
    /// chrome above the list. No-op without a breadcrumb.
    @ViewBuilder
    func detailBreadcrumbChrome<Sort: View>(
        _ crumb: DetailBreadcrumb?,
        @ViewBuilder sort: @escaping () -> Sort
    ) -> some View {
        if let crumb {
            // Same inset as the detail page's own bar on its other sections (no extra gap under
            // the bar), so Scenes and Galleries start at the same height.
            environment(\.detailBreadcrumb, nil)
                .navigationBarHidden(true)
                .stashyCustomChromeInset(spacing: 0) {
                    StashySectionChromeBar {
                        DetailBreadcrumbRow(crumb: crumb) { sort() }
                            .padding(.horizontal, StashyExpandingDock.edgePadding)
                            .padding(.vertical, 6)
                    }
                }
        } else {
            self
        }
    }

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
            title: sections.count == 1 ? (sections.first?.rawValue ?? tr("settings")) : tr("settings"),
            items: sections.map {
                StashyNavMenuItem(id: $0.rawValue, title: $0.rawValue, systemImage: $0.icon)
            },
            selectionID: selection.rawValue,
            titleColor: .white,
            menuAccessibilityLabel: tr("settings_section"),
            menuAccessibilityHint: tr("hint_chooses_which_settings_section_to")
        ) { id in
            if let section = SettingsView.SettingsSection(rawValue: id) {
                selection = section
            }
        }
    }
}
#endif
