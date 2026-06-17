//
//  TVServerDetailView.swift
//  stashyTV
//
//  Detail view for the active server: shows status, version, allows re-test
//  and triggers edit/switch actions. tvOS analog zur iOS-Settings-Server-Detail-Seite.
//

import SwiftUI

struct TVServerDetailView: View {
    @ObservedObject var configManager: ServerConfigManager = .shared
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var isTesting: Bool = false

    private var config: ServerConfig? { configManager.activeConfig }
    private var isConnected: Bool { viewModel.isServerConnected }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let config {
                    headerSection(config: config)
                    statusSection
                    actionsSection(config: config)
                    detailsSection(config: config)
                } else {
                    Text("No server configured.")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 60)
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 60)
            .padding(.top, 40)
        }
        .background(Color.appBackground)
        .navigationTitle(config?.name ?? "Server")
        .onAppear {
            viewModel.testConnection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashServerInitializationFinished)) { _ in
            viewModel.testConnection()
        }
    }

    private func headerSection(config: ServerConfig) -> some View {
        HStack(spacing: 24) {
            Image(systemName: "server.rack")
                .font(.system(size: 60))
                .foregroundColor(appearanceManager.tintColor)
                .frame(width: 100, height: 100)

            VStack(alignment: .leading, spacing: 8) {
                Text(config.name)
                    .font(.largeTitle).fontWeight(.bold)
                Text(config.baseURL)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
        }
    }

    private var statusSection: some View {
        HStack(spacing: 20) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isConnected ? .green : .yellow)
                .font(.title)

            VStack(alignment: .leading, spacing: 4) {
                Text(isConnected ? "Connected" : "Not connected")
                    .font(.title3).fontWeight(.semibold)
                Text(viewModel.serverStatus)
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            if viewModel.isLoading {
                ProgressView()
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func actionsSection(config: ServerConfig) -> some View {
        HStack(spacing: 18) {
            Button {
                isTesting = true
                viewModel.testConnection()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    isTesting = false
                }
            } label: {
                HStack(spacing: 10) {
                    if isTesting { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    Text("Test Connection")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .buttonStyle(.card)
        }
    }

    private func detailsSection(config: ServerConfig) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            row(label: "Protocol", value: config.serverProtocol.displayName)
            row(label: "Address", value: config.serverAddress)
            if let port = config.port, !port.isEmpty {
                row(label: "Port", value: port)
            }
            row(label: "Default Quality", value: config.defaultQuality.displayName)
            row(label: "Reels Quality", value: config.reelsQuality.displayName)
            row(label: "API Key", value: (config.secureApiKey?.isEmpty == false) ? "•••• configured" : "Not set")
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value).foregroundColor(.white)
        }
        .font(.title3)
    }
}
