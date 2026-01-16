//
//  AppearanceManager.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI

class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()
    
    @Published var tintColor: Color {
        didSet {
            // Save to UserDefaults when changed
            saveColor(tintColor)
        }
    }
    
    private let kTintColorRed = "kTintColorRed"
    private let kTintColorGreen = "kTintColorGreen"
    private let kTintColorBlue = "kTintColorBlue"
    private let kTintColorAlpha = "kTintColorAlpha"
    
    private init() {
        // Load from UserDefaults or use default
        self.tintColor = .appAccent
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
            print("❌ Failed to get color components for saving")
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
    
    // Preset Colors
    let presets: [ColorOption] = [
        ColorOption(name: "Stashy Brown", color: .appAccent),
        ColorOption(name: "Blue", color: .blue),
        ColorOption(name: "Red", color: .red),
        ColorOption(name: "Orange", color: .orange),
        ColorOption(name: "Green", color: .green),
        ColorOption(name: "Purple", color: .purple),
        ColorOption(name: "Pink", color: .pink),
        ColorOption(name: "Gray", color: .gray)
    ]
}

struct ColorOption: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let color: Color
}
