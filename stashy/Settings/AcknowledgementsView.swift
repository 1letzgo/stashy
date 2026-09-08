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
              license: "LGPL-3.0, with an App Store / DRM exception",
              note: "Dynamically linked, so the library can be replaced by a modified version.",
              urlString: "https://github.com/superuser404notfound/AetherEngine"),
        Entry(name: "FFmpeg",
              license: "LGPL-2.1 or later",
              note: "Dynamically linked, so relinking with a modified FFmpeg is possible.",
              urlString: "https://ffmpeg.org"),
        Entry(name: "libdovi (dovi_tool)",
              license: "MIT",
              note: nil,
              urlString: "https://github.com/quietvoid/dovi_tool"),
        Entry(name: "dav1d",
              license: "BSD-2-Clause",
              note: nil,
              urlString: "https://code.videolan.org/videolan/dav1d"),
        Entry(name: "PocketSVG",
              license: "MIT",
              note: nil,
              urlString: "https://github.com/pocketsvg/PocketSVG")
    ]

    private let footerText = "stashy uses the components above. Their licenses apply in addition to stashy's own terms."

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
        }
        .navigationTitle("Acknowledgements")
        #else
        List {
            Section {
                stashyScrollingSectionHeader("Components")
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(for: entry)
                        .stashyGroupedBlockRow(index: index, count: entries.count)
                }
                stashyScrollingSectionFooter(footerText)
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome("Acknowledgements")
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
