//
//  HapticManager.swift
//  stashy
//
//  Created by Daniel Goletz on 07.02.26.
//

#if os(iOS)
import UIKit

enum HapticManager {

    // MARK: - Impact Feedback

    /// Light tap - for toggles, selections, small interactions
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Medium tap - for button presses, rating changes
    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// Heavy tap - for destructive actions confirmation
    static func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    // MARK: - Notification Feedback

    /// Success - completed action (rating saved, favorite toggled)
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Error - failed action
    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    /// Warning - caution action
    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    // MARK: - Selection Feedback

    /// Selection changed - for picker/star selection ticks
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}
#elseif os(macOS)
/// macOS has no haptic engine on most hardware; keep the call sites, drop the feedback.
enum HapticManager {
    static func light() {}
    static func medium() {}
    static func heavy() {}
    static func success() {}
    static func error() {}
    static func warning() {}
    static func selection() {}
}
#endif
