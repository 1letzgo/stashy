//
//  AppearanceManager.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI
import Combine

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    case darkBlue = "Dark Blue"
    
    var id: String { self.rawValue }

    /// The name on screen; the raw value is stored.
    var title: String {
        switch self {
        case .system: return tr("system")
        case .light: return tr("light")
        case .dark: return tr("dark")
        case .darkBlue: return tr("dark_blue")
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .darkBlue: return .dark
        }
    }

    /// Themes the tvOS app offers. Light / System are left out: the tvOS UI is drawn
    /// for a dark ground (white labels and focus rings, dark hero fades, overlays).
    static let tvOSThemes: [AppTheme] = [.darkBlue, .dark]
}

class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()
    
    @Published var tintColor: Color {
        didSet {
            // Save to UserDefaults when changed
            saveColor(tintColor)
        }
    }

    @Published var oCounterIcon: String {
        didSet {
            UserDefaults.standard.set(oCounterIcon, forKey: kOCounterIcon)
        }
    }

    /// How see-through the glass chrome is, 0.2 (nearly opaque) … 1 (pure glass).
    /// Applied by `stashyGlass` as a dark wash under the content.
    @Published var glassTransparency: Double {
        didSet {
            UserDefaults.standard.set(glassTransparency, forKey: kGlassTransparency)
        }
    }
    static let defaultGlassTransparency = 1.0
    
    @Published var preferredTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(preferredTheme.rawValue, forKey: kPreferredTheme)
        }
    }

    @Published var isEditModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEditModeEnabled, forKey: kEditModeEnabled)
        }
    }


    var currentTheme: AppTheme {
        #if os(tvOS)
        // tvOS bietet nur die dunklen Themes an (siehe `AppTheme.tvOSThemes`); ein
        // anderer gespeicherter Wert fällt auf den bisherigen Standard zurück.
        return AppTheme.tvOSThemes.contains(preferredTheme) ? preferredTheme : .darkBlue
        #else
        if preferredTheme == .system {
            #if os(iOS)
            return UITraitCollection.current.userInterfaceStyle == .light ? .light : .dark
            #else
            return .dark
            #endif
        }
        return preferredTheme
        #endif
    }

    var oCounterIconFilled: String {
        return oCounterIcon.hasSuffix(".fill") ? oCounterIcon : oCounterIcon + ".fill"
    }

    private let kTintColorRed = "kTintColorRed"
    private let kTintColorGreen = "kTintColorGreen"
    private let kTintColorBlue = "kTintColorBlue"
    private let kTintColorAlpha = "kTintColorAlpha"
    private let kOCounterIcon = "kOCounterIcon"
    private let kGlassTransparency = "kGlassTransparency"
    private let kPreferredTheme = "kPreferredTheme"
    private let kEditModeEnabled = "kEditModeEnabled"


    private init() {
        // Load from UserDefaults or use fresh-install defaults (Dark Blue + Gray).
        self.tintColor = .appDefaultTint
        self.oCounterIcon = UserDefaults.standard.string(forKey: "kOCounterIcon") ?? "heart"
        let storedGlass = UserDefaults.standard.object(forKey: "kGlassTransparency") as? Double
        self.glassTransparency = min(1, max(0.2, storedGlass ?? Self.defaultGlassTransparency))

        let savedTheme = UserDefaults.standard.string(forKey: kPreferredTheme) ?? AppTheme.darkBlue.rawValue
        self.preferredTheme = AppTheme(rawValue: savedTheme) ?? .darkBlue
        let editKeyExists = UserDefaults.standard.object(forKey: "kEditModeEnabled") != nil
        self.isEditModeEnabled = editKeyExists ? UserDefaults.standard.bool(forKey: "kEditModeEnabled") : true

        self.loadColor()
    }
    
    /// Re-reads everything from UserDefaults (after a settings import).
    func reload() {
        oCounterIcon = UserDefaults.standard.string(forKey: kOCounterIcon) ?? "heart"
        let storedGlass = UserDefaults.standard.object(forKey: kGlassTransparency) as? Double
        glassTransparency = min(1, max(0.2, storedGlass ?? Self.defaultGlassTransparency))
        preferredTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: kPreferredTheme) ?? "") ?? .darkBlue
        isEditModeEnabled = UserDefaults.standard.object(forKey: kEditModeEnabled) as? Bool ?? true
        loadColor()
    }

    // MARK: - Persistence
    
    /// `UIColor.getRed` reports success; AppKit's variant returns nothing and traps on
    /// non-RGB colors, so convert to sRGB first there.
    private func rgbaComponents(of color: UIColor, _ r: inout CGFloat, _ g: inout CGFloat, _ b: inout CGFloat, _ a: inout CGFloat) -> Bool {
        #if os(macOS)
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return true
        #else
        return color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
    }

    /// White while it reaches 4.5:1 on the accent colour, black otherwise.
    var onTintColor: Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard rgbaComponents(of: UIColor(tintColor), &red, &green, &blue, &alpha) else { return .white }
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return 1.05 / (luminance + 0.05) >= 4.5 ? .white : .black
    }

    /// Tab bar tint. A gray accent is weaker than the white labels of the other tabs, which
    /// reads as if the selected tab were disabled; neutral accents use the label colour there.
    var tabBarTint: Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard rgbaComponents(of: UIColor(tintColor), &red, &green, &blue, &alpha) else { return tintColor }
        let top = max(red, green, blue)
        let saturation = top > 0 ? (top - min(red, green, blue)) / top : 0
        return saturation < 0.15 ? .primary : tintColor
    }

    private func saveColor(_ color: Color) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        if rgbaComponents(of: uiColor, &red, &green, &blue, &alpha) {
            let defaults = UserDefaults.standard
            defaults.set(Float(red), forKey: kTintColorRed)
            defaults.set(Float(green), forKey: kTintColorGreen)
            defaults.set(Float(blue), forKey: kTintColorBlue)
            defaults.set(Float(alpha), forKey: kTintColorAlpha)
            defaults.synchronize() // Force save just to be safe, though not strictly required in modern iOS
        } else {
            AppLog.debug(NSLocalizedString("appearance.saveColor.failed", comment: "Failed to get color components for saving"))
        }
    }
    
    private func loadColor() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: kTintColorRed) != nil {
            let r = Double(defaults.float(forKey: kTintColorRed))
            let g = Double(defaults.float(forKey: kTintColorGreen))
            let b = Double(defaults.float(forKey: kTintColorBlue))
            let a = Double(defaults.float(forKey: kTintColorAlpha))
            self.tintColor = Color(red: r, green: g, blue: b, opacity: a)
        } else {
            self.tintColor = .appDefaultTint
        }
    }
    
    // Convert current Color to UIColor for UIKit interop if needed
    var uiColor: UIColor {
        return UIColor(tintColor)
    }

    func isSameColor(_ color1: Color, _ color2: Color) -> Bool {
        let uiColor1 = UIColor(color1)
        let uiColor2 = UIColor(color2)
        
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        guard rgbaComponents(of: uiColor1, &r1, &g1, &b1, &a1),
              rgbaComponents(of: uiColor2, &r2, &g2, &b2, &a2) else {
            return false
        }
        
        let threshold: CGFloat = 0.01
        return abs(r1 - r2) < threshold &&
               abs(g1 - g2) < threshold &&
               abs(b1 - b2) < threshold &&
               abs(a1 - a2) < threshold
    }
    
    // Counter Icon Presets
    let oCounterIconPresets: [IconOption] = [
        IconOption(icon: "heart", label: tr("heart")),
        IconOption(icon: "star", label: tr("star")),
        IconOption(icon: "flame", label: tr("flame")),
        IconOption(icon: "bolt", label: tr("bolt")),
        IconOption(icon: "hand.thumbsup", label: tr("thumbs_up")),
        IconOption(icon: "circle", label: tr("circle")),
        IconOption(icon: "diamond", label: tr("diamond")),
        IconOption(icon: "crown", label: tr("crown")),
        IconOption(icon: "trophy", label: tr("trophy")),
        IconOption(icon: "moon", label: tr("moon")),
        IconOption(icon: "drop", label: tr("drop")),
        IconOption(icon: "leaf", label: tr("leaf")),
        IconOption(icon: "bell", label: tr("bell")),
        IconOption(icon: "tag", label: tr("tag")),
        IconOption(icon: "eye", label: tr("eye")),
    ]

    // Preset Colors
    var presets: [ColorOption] { [
        ColorOption(nameKey: tr("stashy_brown"), color: .appAccent),
        ColorOption(nameKey: tr("blue"), color: .blue),
        ColorOption(nameKey: tr("red"), color: .red),
        ColorOption(nameKey: tr("orange"), color: .orange),
        ColorOption(nameKey: tr("green"), color: .green),
        ColorOption(nameKey: tr("purple"), color: .purple),
        ColorOption(nameKey: tr("pink"), color: .pink),
        ColorOption(nameKey: tr("gray"), color: .gray)
    ] }
}

struct IconOption: Identifiable, Hashable {
    let id = UUID()
    let icon: String
    let label: String
}

struct ColorOption: Identifiable, Hashable {
    let id = UUID()
    let nameKey: String
    let color: Color

    var localizedName: String {
        return nameKey // We are currently using strings directly, no localizations detected yet.
    }
}

