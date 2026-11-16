//
//  TVMarkerNavigation.swift
//  stashyTV
//
//  Where a marker list starts and where Previous / Next Marker go. Shared by the player's
//  marker row, its marker rail and the scene page's marker section, so all three agree.
//  Previous allows more slack than the phone player (3 s instead of 1 s): on the TV the press
//  comes later after a jump, and the playhead lags behind a seek.
//

import Foundation

enum TVMarkerNavigation {

    /// The marker a list opens on: the last one starting at or before `time`, the first one
    /// while `time` lies before every marker. `starts` sorted ascending; nil when empty.
    static func entryIndex(starts: [Double], time: Double) -> Int? {
        guard !starts.isEmpty else { return nil }
        return starts.lastIndex { $0 <= time } ?? 0
    }

    /// Within the first seconds of a marker Previous goes to the marker before it (so repeated
    /// presses walk back); later it restarts the current marker.
    static let previousRestartSlack: Double = 3

    static func previous(starts: [Double], from time: Double) -> Double? {
        starts.last { $0 < time - previousRestartSlack }
    }

    /// The time Previous / Next decide from. Right after a jump the engine still reports the
    /// old position (or a keyframe before the target), so until it has landed at or just after
    /// the target, the target counts. `jump` = target and time of the last marker jump.
    static func referenceTime(playhead: Double, jump: (target: Double, at: Date)?, now: Date = Date()) -> Double {
        guard let jump, now.timeIntervalSince(jump.at) < 8 else { return playhead }
        let landed = playhead >= jump.target - 0.5 && playhead <= jump.target + 8
        return landed ? playhead : jump.target
    }

    static func next(starts: [Double], from time: Double) -> Double? {
        starts.first { $0 > time + 0.5 }
    }
}
