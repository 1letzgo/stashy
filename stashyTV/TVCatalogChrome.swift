//
//  TVCatalogChrome.swift
//  stashyTV
//
//  Gemeinsame Chrome für alle Katalog-Grids: Sort-/Filter-Picker und das
//  Grid-Gerüst (Config-/Error-/Loading-/Empty-/Content-Zustände).
//
//  Warum `confirmationDialog` statt `Menu`:
//  Auf tvOS reicht `.buttonStyle(.card)` nicht zuverlässig an ein Menu-Label
//  durch — der Fokus-Zustand ist dann unsichtbar. Ein echter Button plus
//  `confirmationDialog` ist die native Variante (so macht es auch
//  `TVSceneDetailView` für Rating/Quality) und kommt ohne Submenüs aus.
//

import SwiftUI

// MARK: - Picker-Optionen

struct TVPickerOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }

    init(_ value: Value, _ label: String) {
        self.value = value
        self.label = label
    }
}

/// Card-Button, der eine flache Optionsliste als Action-Sheet öffnet.
struct TVOptionPickerButton<Value: Hashable>: View {
    let title: String
    let icon: String
    let options: [TVPickerOption<Value>]
    @Binding var selection: Value

    @State private var isPresented = false

    private var currentLabel: String {
        options.first(where: { $0.value == selection })?.label ?? title
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            TVChromeButtonLabel(icon: icon, text: currentLabel)
        }
        .buttonStyle(.card)
        .confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
            ForEach(options) { option in
                Button(option.value == selection ? "✓ \(option.label)" : option.label) {
                    selection = option.value
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Card-Button für die Server-seitigen Saved Filters.
struct TVFilterPickerButton: View {
    let filters: [StashDBViewModel.SavedFilter]
    @Binding var selection: StashDBViewModel.SavedFilter?

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            TVChromeButtonLabel(
                icon: selection != nil
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle",
                text: selection?.name ?? "No Filter"
            )
        }
        .buttonStyle(.card)
        .confirmationDialog("Filter", isPresented: $isPresented, titleVisibility: .visible) {
            Button(selection == nil ? "✓ No Filter" : "No Filter") {
                selection = nil
            }
            ForEach(filters) { filter in
                Button(selection?.id == filter.id ? "✓ \(filter.name)" : filter.name) {
                    selection = filter
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct TVChromeButtonLabel: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.headline)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

// MARK: - Grid-Gerüst

/// Kapselt die Zustandsabfolge, das Grid, Paging, Fokus und den Bottom-Inset,
/// die zuvor in jeder der sieben Katalog-Views einzeln standen.
///
/// `Item` braucht bewusst nur `Identifiable` — `TVGridItem` deckt nur
/// Performer/Studio/Tag/Group ab, nicht Scene/Gallery/Image.
struct TVCatalogGrid<Item: Identifiable, Card: View, Header: View>: View where Item.ID == String {
    let items: [Item]
    let hasValidConfig: Bool
    let errorMessage: String?
    let isLoading: Bool
    let isLoadingMore: Bool
    let hasMore: Bool
    let columnWidth: CGFloat
    /// **Maximum**, nicht Fixwert — die tatsächliche Spaltenzahl richtet sich
    /// nach der verfügbaren Breite (Sidebar!) und wird nie größer als dieser Wert.
    var columnCount: Int = 4
    var columnSpacing: CGFloat = 40
    var minColumns: Int = 2
    let emptySystemImage: String
    let emptyTitle: String
    let loadingText: String
    let errorTitle: String
    /// Wird hochgezählt, wenn Sortierung oder Filter absichtlich gewechselt
    /// wurden — nur dann darf der Fokus zurück nach oben springen.
    let focusResetToken: Int
    let loadMore: () -> Void
    let reload: () -> Void

    @FocusState.Binding var focusedID: String?
    @ViewBuilder let header: () -> Header
    @ViewBuilder let card: (Item) -> Card

    @State private var pendingFocusReset = false
    @Environment(\.tvContentWidth) private var contentWidth

    private var gridSpec: TVGridSpec {
        TVGridSpec(
            columnWidth: columnWidth,
            spacing: columnSpacing,
            maxColumns: columnCount,
            minColumns: min(minColumns, columnCount)
        )
    }

    private var columns: [GridItem] {
        gridSpec.columns(for: contentWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hasValidConfig {
                TVConnectionErrorView(
                    title: "Server not reachable",
                    subtitle: "Add a server in Settings."
                ) { reload() }
            } else if items.isEmpty && (errorMessage?.isEmpty == false) {
                TVConnectionErrorView(title: errorTitle, subtitle: errorMessage) { reload() }
            } else if isLoading && items.isEmpty {
                loadingView
            } else if items.isEmpty {
                emptyView
            } else {
                contentGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .onChange(of: focusResetToken) { _, _ in
            pendingFocusReset = true
        }
        .onChange(of: items.first?.id) { _, newID in
            // Fokus nur nach einem gewollten Sort-/Filterwechsel zurücksetzen.
            // Ein Hintergrund-Refetch darf den Nutzer nicht aus dem Grid reißen.
            guard pendingFocusReset, let newID else { return }
            pendingFocusReset = false
            focusedID = newID
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        Spacer()
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5)
            Text(loadingText)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        // `TVScenesView` wird vom Dashboard aus gepusht — ohne fokussierbares
        // Element erreicht die Menu-Taste `tvExitDismissable` nicht.
        .focusable()
        Spacer()
    }

    @ViewBuilder
    private var emptyView: some View {
        Spacer()
        VStack(spacing: 24) {
            Image(systemName: emptySystemImage)
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            Text(emptyTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Button {
                reload()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.title3)
            }
        }
        Spacer()
    }

    @ViewBuilder
    private var contentGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header()

                LazyVGrid(columns: columns, alignment: .leading, spacing: columnSpacing) {
                    ForEach(items) { item in
                        card(item)
                            .focused($focusedID, equals: item.id)
                            .frame(width: columnWidth)
                            .onAppear {
                                if item.id == items.last?.id && hasMore {
                                    loadMore()
                                }
                            }
                    }

                    if isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 80)
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 60).focusable(false) }
    }
}

// MARK: - Settings-Zeile mit Auswahl

/// List-Zeile mit Auswahl. Als echter `Button` bekommt sie auf tvOS die
/// normale Zeilen-Fokus-Hervorhebung — ein blankes `Text`-Label als
/// `Menu`-Trigger hatte gar keine.
struct TVSettingsPickerRow<Value: Hashable>: View {
    let title: String
    let options: [TVPickerOption<Value>]
    @Binding var selection: Value

    @State private var isPresented = false

    private var currentLabel: String {
        options.first(where: { $0.value == selection })?.label ?? "—"
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(currentLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
            ForEach(options) { option in
                Button(option.value == selection ? "✓ \(option.label)" : option.label) {
                    selection = option.value
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
