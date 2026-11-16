//
//  TVMarkerNavigation.swift
//  stashyTV
//
//  Where a marker list starts and where Previous / Next Marker go. Shared by the player's
//  marker row, its marker rail and the scene page's marker section, so all three agree.
//  Same rules as the phone player (`AetherSceneSurface.previousMarkerSeconds` / `next…`).
//

import Foundation

enum TVMarkerNavigation {

    /// The marker a list opens on: the last one starting at or before `time`, the first one
    /// while `time` lies before every marker. `starts` sorted ascending; nil when empty.
    static func entryIndex(starts: [Double], time: Double) -> Int? {
        guard !starts.isEmpty else { return nil }
        return starts.lastIndex { $0 <= time } ?? 0
    }

    /// Previous = the last marker starting at least a second before `time`, so a press right
    /// after a jump goes one further back instead of restarting the same marker.
    static func previous(starts: [Double], from time: Double) -> Double? {
        starts.last { $0 < time - 1 }
    }

    static func next(starts: [Double], from time: Double) -> Double? {
        starts.first { $0 > time + 0.5 }
    }
}
