//
//  AcknowledgementsView.swift
//  stashy
//
//  Third-party components and their licenses.
//

import SwiftUI

struct AcknowledgementsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    private struct Entry: Identifiable {
        let id = UUID()
        let name: String
        let license: String
        let note: String?
        let urlString: String
    }

    private let entries: [Entry] = [
        Entry(name: "AetherEngine",
              license: tr("hint_lgpl_3_0_with_app"),
              note: tr("hint_dynamically_linked_so_library_can"),
              urlString: "https://github.com/superuser404notfound/AetherEngine"),
        Entry(name: "FFmpeg",
              license: tr("lgpl_2_1_or_later"),
              note: tr("hint_dynamically_linked_so_relinking_with"),
              urlString: "https://ffmpeg.org"),
        Entry(name: "libdovi (dovi_tool)",
              license: "MIT",
              note: nil,
              urlString: "https://github.com/quietvoid/dovi_tool"),
        Entry(name: "dav1d",
              license: "BSD-2-Clause",
              note: nil,
              urlString: "https://code.videolan.org/videolan/dav1d"),
        Entry(name: "SwiftDraw",
              license: "zlib",
              note: nil,
              urlString: "https://github.com/swhitty/SwiftDraw")
    ]

    /// Where the app's wording and translations come from.
    private let translationEntries: [Entry] = [
        Entry(name: "Stash",
              license: "AGPL-3.0",
              note: tr("hint_terms_follow_stashs_own_interface"),
              urlString: "https://github.com/stashapp/stash"),
        Entry(name: "Tolgee",
              license: "Apache-2.0",
              note: tr("translations_are_managed_with_tolgee"),
              urlString: "https://tolgee.io")
    ]

    private let footerText = tr("hint_stashy_uses_components_above_their")

    var body: some View {
        #if os(tvOS)
        // The grouped settings chrome helpers are iOS-only; tvOS keeps a plain list.
        List {
            Section {
                ForEach(entries) { entry in
                    row(for: entry)
                }
            } footer: {
                Text(footerText)
            }
            Section(tr("translations")) {
                ForEach(translationEntries) { entry in
                    row(for: entry)
                }
            }
        }
        .navigationTitle(tr("acknowledgements"))
        #else
        List {
            Section {
                stashyScrollingSectionHeader(tr("components"))
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(for: entry)
                        .stashyGroupedBlockRow(index: index, count: entries.count)
                }
                stashyScrollingSectionFooter(footerText)
            }
            Section {
                stashyScrollingSectionHeader(tr("translations"))
                ForEach(Array(translationEntries.enumerated()), id: \.element.id) { index, entry in
                    row(for: entry)
                        .stashyGroupedBlockRow(index: index, count: translationEntries.count)
                }
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome(tr("acknowledgements"))
        #endif
    }

    @ViewBuilder
    private func row(for entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.name)
                .font(.headline)
            Text(entry.license)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let note = entry.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let url = URL(string: entry.urlString) {
                Link(entry.urlString, destination: url)
                    .font(.caption)
                    .tint(appearanceManager.tintColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
