#if !os(tvOS)
import SwiftUI

/// Secondary entry point to the full Stash criteria editor from a catalog filter sheet.
///
/// The quick chips stay the primary surface; everything Stash can express (AND/OR/NOT, nested
/// filters, regex, custom fields, …) lives one tap deeper and applies on `Done`, so editing
/// criteria never refetches per keystroke.
struct AdvancedCriteriaCard: View {
    @ObservedObject var document: FilterCriteriaDocument
    /// Called once when the editor is committed (or cleared), never while typing.
    var onApply: () -> Void

    @State private var isEditorPresented = false
    @ObservedObject private var appearance = AppearanceManager.shared

    private var activeCount: Int { document.activeCriterionCount }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                isEditorPresented = true
            } label: {
                HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                    Text("Advanced")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
                    Text(activeCount == 0 ? "No criteria" : "\(activeCount) criteria")
                        .font(.subheadline)
                        .foregroundColor(activeCount == 0 ? .secondary : .primary)
                    Spacer(minLength: DesignTokens.Spacing.xs)
                    if activeCount > 0 {
                        Circle()
                            .fill(appearance.tintColor)
                            .frame(width: DesignTokens.Chrome.fabActiveDot, height: DesignTokens.Chrome.fabActiveDot)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if activeCount > 0 {
                Divider().padding(.leading, DesignTokens.Spacing.md)
                Button {
                    document.clear()
                    HapticManager.selection()
                    onApply()
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: "xmark.circle")
                        Text("Clear advanced criteria")
                            .font(.subheadline)
                        Spacer()
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .padding(.horizontal, DesignTokens.Spacing.md)
        .sheet(isPresented: $isEditorPresented) {
            AdvancedCriteriaEditorSheet(document: document, onCommit: onApply)
        }
    }
}

/// Full-screen criteria editor. Edits a scratch copy, so Cancel really cancels.
private struct AdvancedCriteriaEditorSheet: View {
    @ObservedObject var document: FilterCriteriaDocument
    var onCommit: () -> Void

    @StateObject private var scratch: FilterCriteriaDocument
    @Environment(\.dismiss) private var dismiss

    init(document: FilterCriteriaDocument, onCommit: @escaping () -> Void) {
        self.document = document
        self.onCommit = onCommit
        _scratch = StateObject(wrappedValue: FilterCriteriaDocument(
            mode: document.mode,
            objectFilter: document.sanitizedObjectFilter
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                FilterCriteriaEditorView(document: scratch)
            }
            .padding(.top, DesignTokens.Spacing.xs)
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .stashyModalSheetChrome("Advanced criteria", onBack: { dismiss() }) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                if !scratch.isEmpty {
                    Button {
                        scratch.clear()
                    } label: {
                        Text("Clear")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.red)
                            .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    document.replaceObjectFilter(scratch.sanitizedObjectFilter)
                    HapticManager.selection()
                    onCommit()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight))
                }
                .buttonStyle(.plain)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
    }
}
#endif
