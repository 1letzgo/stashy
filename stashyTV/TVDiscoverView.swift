//
//  TVDiscoverView.swift
//  stashyTV
//
//  "Discover" sidebar entry: the tvOS counterpart of the iOS Tools → Discover group
//  (Match, RateMe). Both are stashy+ tools; while stashy+ is locked the tiles stay visible
//  with a lock and open the stashy+ page instead, like the paywall that replaces Tools on iOS.
//

import SwiftUI

enum TVDiscoverTool: String, Hashable, CaseIterable, Identifiable {
    case match
    case rateMe

    var id: String { rawValue }

    /// Same names and icons as `ToolsItem` on iOS.
    var title: String {
        switch self {
        case .match: return ToolsItem.hotOrNot.title
        case .rateMe: return ToolsItem.rateMe.title
        }
    }

    var systemImage: String {
        switch self {
        case .match: return ToolsItem.hotOrNot.icon
        case .rateMe: return ToolsItem.rateMe.icon
        }
    }

    var subtitle: String {
        switch self {
        case .match: return "Pick the winner of two performers. Ratings follow the Ascension plugin."
        case .rateMe: return "Rate unrated scenes and images, one after another."
        }
    }
}

/// Pushes a Discover tool onto the Discover stack.
struct TVDiscoverToolLink: Hashable {
    let tool: TVDiscoverTool
}

/// Pushes the stashy+ page (from a locked tool tile).
struct TVDiscoverStashyPlusLink: Hashable {}

struct TVDiscoverView: View {
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    @ObservedObject private var appearance = AppearanceManager.shared
    @Environment(\.tvNavigationPath) private var path

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 40) {
                Text("Discover")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                HStack(alignment: .top, spacing: 48) {
                    ForEach(TVDiscoverTool.allCases) { tool in
                        tile(tool)
                    }
                }
                .focusSection()

                if !stashyPlus.isUnlocked {
                    Label("Match and RateMe are part of stashy+.", systemImage: "lock.fill")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appBackground)
        .navigationDestination(for: TVDiscoverToolLink.self) { link in
            TVDiscoverToolDestination(tool: link.tool)
                .tvExitDismissable()
                .environment(\.tvNavigationPath, path)
        }
        .navigationDestination(for: TVDiscoverStashyPlusLink.self) { _ in
            TVStashyPlusSettingsView()
                .tvExitDismissable()
                .environment(\.tvNavigationPath, path)
        }
    }

    private func tile(_ tool: TVDiscoverTool) -> some View {
        let locked = !stashyPlus.isUnlocked
        return Button {
            if locked {
                path?.wrappedValue.append(TVDiscoverStashyPlusLink())
            } else {
                path?.wrappedValue.append(TVDiscoverToolLink(tool: tool))
            }
        } label: {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(appearance.tintColor)
                    Spacer()
                    if locked {
                        Label("stashy+", systemImage: "lock.fill")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                Spacer(minLength: 0)
                Text(tool.title)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(tool.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(36)
            .frame(width: 560, height: 340, alignment: .topLeading)
            .background(Color.secondaryAppBackground)
            .opacity(locked ? 0.75 : 1)
        }
        .buttonStyle(.card)
        .accessibilityLabel(locked ? "\(tool.title), requires stashy+" : tool.title)
    }
}

/// Re-checks the entitlement on the pushed page: an expiring subscription must not leave a
/// tool open behind the lock.
private struct TVDiscoverToolDestination: View {
    let tool: TVDiscoverTool
    @ObservedObject private var stashyPlus = StashyPlusManager.shared

    var body: some View {
        if stashyPlus.isUnlocked {
            switch tool {
            case .match: TVMatchView()
            case .rateMe: TVRateMeView()
            }
        } else {
            TVStashyPlusSettingsView()
        }
    }
}
