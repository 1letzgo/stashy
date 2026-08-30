//
//  OpenSourceNotices.swift
//  stashy
//
//  Third-party license notices.
//
//  Not decoration: FFmpeg and friends reach the app under LGPL, and shipping
//  them in a paid App Store build obliges us to reproduce their license texts
//  and point at the exact source build. The frameworks are embedded
//  dynamically in `stashy.app/Frameworks/` (never merged into the app binary)
//  so the LGPL section 6 relink requirement stays satisfiable.
//

import SwiftUI

struct OpenSourceNotice: Identifiable {
    var id: String { name }
    let name: String
    let license: String
    /// Source of the exact build shipped, pinned to a tag where one exists.
    let source: String
    let note: String
}

enum OpenSourceNotices {
    static let all: [OpenSourceNotice] = [
        OpenSourceNotice(
            name: "AetherEngine 6.56.5",
            license: "LGPL-3.0 with Apple Store / DRM Exception",
            source: "https://github.com/superuser404notfound/AetherEngine/releases/tag/6.56.5",
            note: "Media player engine behind stashy+ Direct Play."
        ),
        OpenSourceNotice(
            name: "FFmpeg 8.1 (libavcodec, libavformat, libavutil, libavfilter, libswresample, libswscale)",
            license: "LGPL-2.1-or-later",
            source: "https://github.com/superuser404notfound/FFmpegBuild/releases/tag/2.5.0",
            note: "Built without --enable-gpl and without --enable-version3. Shipped as dynamic frameworks in stashy.app/Frameworks/."
        ),
        OpenSourceNotice(
            name: "dav1d 1.5.4",
            license: "BSD-2-Clause",
            source: "https://code.videolan.org/videolan/dav1d",
            note: "AV1 software decoder."
        ),
        OpenSourceNotice(
            name: "zimg 3.0.6",
            license: "WTFPL",
            source: "https://github.com/sekrit-twc/zimg",
            note: "Colorspace backend for zscale."
        ),
        OpenSourceNotice(
            name: "libzvbi 0.2.45",
            license: "LGPL-2.0-or-later (ure.c: MIT)",
            source: "https://github.com/superuser404notfound/FFmpegBuild/releases/tag/2.5.0",
            note: "DVB teletext decoding. The three GPL-2 sources are excluded from the build."
        ),
        OpenSourceNotice(
            name: "libdovi (dovi_tool) 3.4.0",
            license: "MIT",
            source: "https://github.com/quietvoid/dovi_tool",
            note: "Copyright (c) quietvoid and contributors. Dolby Vision RPU parsing."
        ),
        OpenSourceNotice(
            name: "PocketSVG",
            license: "MIT",
            source: "https://github.com/pocketsvg/PocketSVG",
            note: "SVG rendering on tvOS."
        ),
    ]
}

/// Acknowledgements screen. Shared by the iOS and tvOS settings surfaces —
/// the license obligation applies to both builds.
struct OpenSourceNoticesView: View {
    var body: some View {
        List {
            Section {
                Text("stashy uses the open-source components below. Each is distributed under its own license; the linked source is the exact build shipped in this app.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            ForEach(OpenSourceNotices.all) { notice in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(notice.name)
                            .font(.headline)
                        Text(notice.license)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(notice.note)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        sourceLabel(notice.source)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Acknowledgements")
    }

    /// tvOS has no text selection; there it is a plain, copy-free line.
    @ViewBuilder
    private func sourceLabel(_ source: String) -> some View {
        let text = Text(source)
            .font(.caption)
            .foregroundColor(.secondary)
        #if os(tvOS)
        text
        #else
        text.textSelection(.enabled)
        #endif
    }
}
