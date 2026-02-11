//
//  OnboardingView.swift
//  stashy
//
//  Welcome screen for first-time users
//

#if !os(tvOS)
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var showingAddServer = false
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Spacer()
                
                // Hero Section
                VStack(spacing: 24) {
                    // App Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [appearanceManager.tintColor, appearanceManager.tintColor.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "play.rectangle.on.rectangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                    .shadow(color: appearanceManager.tintColor.opacity(0.4), radius: 20, y: 10)
                    
                    VStack(spacing: 8) {
                        Text("Welcome to stashy")
                            .font(.largeTitle.bold())
                        
                        Text("Your personal Stash companion")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Features List
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(
                        icon: "server.rack",
                        color: .blue,
                        title: "Connect to Stash",
                        description: "Stream your library from anywhere"
                    )
                    
                    FeatureRow(
                        icon: "icloud.and.arrow.down",
                        color: .green,
                        title: "Offline Downloads",
                        description: "Save scenes for offline viewing"
                    )
                    
                    FeatureRow(
                        icon: "rectangle.on.rectangle",
                        color: .purple,
                        title: "Native Experience",
                        description: "Built for iOS with familiar gestures"
                    )
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // CTA Button
                VStack(spacing: 16) {
                    Button(action: { showingAddServer = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Your Server")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(appearanceManager.tintColor)
                        .foregroundColor(.white)
                        .cornerRadius(DesignTokens.CornerRadius.button)
                    }
                    
                    Text("You'll need a running Stash server to continue")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .sheet(isPresented: $showingAddServer) {
                ServerSetupWizardView { newConfig in
                    ServerConfigManager.shared.addOrUpdateServer(newConfig)
                    ServerConfigManager.shared.saveConfig(newConfig)
                    isPresented = false
                }
            }
        }
    }
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
#endif
