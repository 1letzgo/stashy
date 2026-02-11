//
//  TVHapticManager.swift
//  stashyTV
//
//  No-op stub for tvOS. Haptic feedback is not available on Apple TV.
//

import Foundation

enum HapticManager {
    static func light() {}
    static func medium() {}
    static func heavy() {}
    static func success() {}
    static func error() {}
    static func warning() {}
    static func selection() {}
}
