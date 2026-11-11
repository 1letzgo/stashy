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
            glassSection
            counterIconSection
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome(tr("appearance"))
    }

    private var themeSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("app_theme"))
            Picker(tr("theme"), selection: $appearanceManager.preferredTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .stashyGroupedSettingsRow()
            stashyScrollingSectionFooter(tr("hint_choose_appearance_of_app"))
        }
    }

    private var glassSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("glass"))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(tr("transparency"), systemImage: "circle.lefthalf.filled")
                    Spacer()
                    Text("\(Int((appearanceManager.glassTransparency * 100).rounded())) %")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $appearanceManager.glassTransparency, in: 0.2...1, step: 0.05)
                    .tint(appearanceManager.tintColor)
            }
            .stashyGroupedBlockRow(index: 0, count: 2)

            glassDemo
                .stashyGroupedBlockRow(index: 1, count: 2)
            stashyScrollingSectionFooter(tr("hint_how_much_of_content_shows"))
        }
    }

    /// Live preview: the three chrome shapes on a busy backdrop, redrawn with the slider.
    private var glassDemo: some View {
        ZStack {
            LinearGradient(
                colors: [.orange, .pink, .purple, .blue, .teal, .green],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<8, id: \.self) { col in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity((row + col) % 2 == 0 ? 0.55 : 0.1))
                                .frame(height: 10)
                        }
                    }
                }
            }
            .padding(10)

            HStack(spacing: 10) {
                Button {} label: {
                    HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                        Text(tr("back"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(Color.onAppTint)
                    .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight, accent: true))
                }
                Button {} label: {
                    Text(tr("demo"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight))
                }
                Button {} label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .stashyGlass(shape: Circle())
                }
            }
            .buttonStyle(.plain)
            .colorScheme(.dark)
            .allowsHitTesting(false)
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.vertical, 4)
        .accessibilityLabel(tr("glass_preview"))
    }

    private var accentColorSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("app_accent_color"))
            ColorPicker(tr("custom_color"), selection: $appearanceManager.tintColor, supportsOpacity: false)
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
            stashyScrollingSectionFooter(tr("hint_this_color_will_be_applied"))
        }
    }

    private var counterIconSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("o_count"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 12) {
                ForEach(appearanceManager.oCounterIconPresets) { option in
                    counterIconItem(for: option)
                }
            }
            .padding(.vertical, 8)
            .stashyGroupedSettingsRow()
            stashyScrollingSectionFooter(tr("hint_choose_which_icon_to_display"))
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
                .font(.system(size: 11))
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
