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
            themeSection
            accentColorSection
            counterIconSection
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome("Appearance")
    }

    private var themeSection: some View {
        Section {
            stashyScrollingSectionHeader("App Theme")
            Picker("Theme", selection: $appearanceManager.preferredTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .stashyGroupedSettingsRow()
            stashyScrollingSectionFooter("Choose the appearance of the app.")
        }
    }

    private var accentColorSection: some View {
        Section {
            stashyScrollingSectionHeader("App Accent Color")
            ColorPicker("Custom Color", selection: $appearanceManager.tintColor, supportsOpacity: false)
                .stashyGroupedBlockRow(index: 0, count: 2)

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
                                .opacity(appearanceManager.isSameColor(appearanceManager.tintColor, option.color) ? 1 : 0)
                        )
                        .onTapGesture {
                            withAnimation {
                                appearanceManager.tintColor = option.color
                            }
                        }
                }
            }
            .padding(.vertical, 8)
            .stashyGroupedBlockRow(index: 1, count: 2)
            stashyScrollingSectionFooter("This color will be applied to the tab bar, navigation bar buttons, and other interactive elements throughout the app.")
        }
    }

    private var counterIconSection: some View {
        Section {
            stashyScrollingSectionHeader("O Counter")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 12) {
                ForEach(appearanceManager.oCounterIconPresets) { option in
                    counterIconItem(for: option)
                }
            }
            .padding(.vertical, 8)
            .stashyGroupedSettingsRow()
            stashyScrollingSectionFooter("Choose which icon to display for the O Counter throughout the app.")
        }
    }

    private func counterIconItem(for option: IconOption) -> some View {
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
#endif
