//
//  AppearanceManager.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI
import Combine

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

    var oCounterIconFilled: String {
        return oCounterIcon.hasSuffix(".fill") ? oCounterIcon : oCounterIcon + ".fill"
    }

    private let kTintColorRed = "kTintColorRed"
    private let kTintColorGreen = "kTintColorGreen"
    private let kTintColorBlue = "kTintColorBlue"
    private let kTintColorAlpha = "kTintColorAlpha"
    private let kOCounterIcon = "kOCounterIcon"

    private init() {
        // Load from UserDefaults or use default
        self.tintColor = .appAccent
        self.oCounterIcon = UserDefaults.standard.string(forKey: "kOCounterIcon") ?? "heart"
        self.loadColor()
    }
    
    // MARK: - Persistence
    
    private func saveColor(_ color: Color) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let defaults = UserDefaults.standard
            defaults.set(Float(red), forKey: kTintColorRed)
            defaults.set(Float(green), forKey: kTintColorGreen)
            defaults.set(Float(blue), forKey: kTintColorBlue)
            defaults.set(Float(alpha), forKey: kTintColorAlpha)
            defaults.synchronize() // Force save just to be safe, though not strictly required in modern iOS
        } else {
            print(NSLocalizedString("appearance.saveColor.failed", comment: "Failed to get color components for saving"))
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
            // Default color
            self.tintColor = .appAccent
        }
    }
    
    // Convert current Color to UIColor for UIKit interop if needed
    var uiColor: UIColor {
        return UIColor(tintColor)
    }
    
    // Counter Icon Presets
    let oCounterIconPresets: [IconOption] = [
        IconOption(icon: "heart", label: "Heart"),
        IconOption(icon: "star", label: "Star"),
        IconOption(icon: "flame", label: "Flame"),
        IconOption(icon: "bolt", label: "Bolt"),
        IconOption(icon: "hand.thumbsup", label: "Thumbs Up"),
        IconOption(icon: "circle", label: "Circle"),
        IconOption(icon: "diamond", label: "Diamond"),
        IconOption(icon: "crown", label: "Crown"),
        IconOption(icon: "trophy", label: "Trophy"),
        IconOption(icon: "moon", label: "Moon"),
        IconOption(icon: "drop", label: "Drop"),
        IconOption(icon: "leaf", label: "Leaf"),
        IconOption(icon: "bell", label: "Bell"),
        IconOption(icon: "tag", label: "Tag"),
        IconOption(icon: "eye", label: "Eye"),
    ]

    // Preset Colors
    let presets: [ColorOption] = [
        ColorOption(nameKey: "appearance.presets.stashy_brown", color: .appAccent),
        ColorOption(nameKey: "appearance.presets.blue", color: .blue),
        ColorOption(nameKey: "appearance.presets.red", color: .red),
        ColorOption(nameKey: "appearance.presets.orange", color: .orange),
        ColorOption(nameKey: "appearance.presets.green", color: .green),
        ColorOption(nameKey: "appearance.presets.purple", color: .purple),
        ColorOption(nameKey: "appearance.presets.pink", color: .pink),
        ColorOption(nameKey: "appearance.presets.gray", color: .gray)
    ]
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
        NSLocalizedString(nameKey, comment: "Preset color name")
    }
}
