//
//  TVConnectionErrorView.swift
//  stashyTV
//
//  tvOS counterpart to iOS `ConnectionErrorView` in NavigationCoordinator.swift
//  (that file is not built for tvOS). Used when the Stash server is unreachable
//  or configuration is missing — same pattern as ScenesView / list screens.
//

import SwiftUI

struct TVConnectionErrorView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    var title: String = tr("server_not_reachable")
    var subtitle: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 200)

            Image(systemName: "server.rack")
                .font(.system(size: 80))
                .foregroundStyle(appearanceManager.tintColor)

            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 80)
            }

            Button(tr("action_retry_connection"), action: onRetry)
                .font(.title3)

            Spacer(minLength: 200)
        }
        .frame(maxWidth: .infinity)
    }
}
