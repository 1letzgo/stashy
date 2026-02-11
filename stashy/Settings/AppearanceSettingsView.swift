//
//  AppearanceSettingsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

#if !os(tvOS)
import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        List {
            
            Section(header: Text("App Accent Color"), footer: Text("This color will be applied to the tab bar, navigation bar buttons, and other interactive elements throughout the app.")) {
                // Color Picker
                ColorPicker("Custom Color", selection: $appearanceManager.tintColor, supportsOpacity: false)
                
                // Presets Grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                    ForEach(appearanceManager.presets) { option in
                        Circle()
                            .fill(option.color)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                            )
                            .overlay(
                                Image(systemName: "checkmark")
                                    .foregroundColor(.white)
                                    .opacity(appearanceManager.tintColor == option.color ? 1 : 0)
                            )
                            .onTapGesture {
                                withAnimation {
                                    appearanceManager.tintColor = option.color
                                }
                            }
                    }
                }
                .padding(.vertical, 8)
            }
            Section(header: Text("Counter Icon"), footer: Text("Choose which icon to display for the Counter throughout the app.")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 12) {
                    ForEach(appearanceManager.oCounterIconPresets) { option in
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(appearanceManager.oCounterIcon == option.icon
                                          ? appearanceManager.tintColor.opacity(0.15)
                                          : Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Circle()
                                            .stroke(appearanceManager.oCounterIcon == option.icon
                                                    ? appearanceManager.tintColor
                                                    : Color.primary.opacity(0.2), lineWidth: appearanceManager.oCounterIcon == option.icon ? 2 : 1)
                                    )

                                Image(systemName: option.icon + ".fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(appearanceManager.oCounterIcon == option.icon
                                                     ? appearanceManager.tintColor
                                                     : .primary.opacity(0.6))
                            }

                            Text(option.label)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .onTapGesture {
                            HapticManager.selection()
                            withAnimation(DesignTokens.Animation.quick) {
                                appearanceManager.oCounterIcon = option.icon
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Appearance")
    }
}
#endif
