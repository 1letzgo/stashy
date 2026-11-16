//
//  TVMarkerNavigation.swift
//  stashyTV
//
//  Where a marker list starts and where Previous / Next Marker go. Shared by the player's
//  marker row, its marker rail and the scene page's marker section, so all three agree.
//  Android: `TvMarkerNav` in TvLogic.kt (same rules, unit-tested there).
//

import Foundation

enum TVMarkerNavigation {

    /// The marker a list opens on: the last one starting at or before `time`, the first one
    /// while `time` lies before every marker. `starts` sorted ascending; nil when empty.
    static func entryIndex(starts: [Double], time: Double) -> Int? {
        guard !starts.isEmpty else { return nil }
        return starts.lastIndex { $0 <= time } ?? 0
    }

    /// The marker last jumped to (Previous / Next or a pick in the rail). Cleared by the player
    /// on any manual seek.
    struct Jump: Equatable {
        let index: Int
        let at: Date
    }

    /// Previous / Next as marker indexes. The row's labels and its actions both read this one
    /// result, so they can never disagree.
    struct Targets: Equatable {
        let previous: Int?
        let next: Int?
    }

    /// While the seek is in flight the engine still reports the old position.
    static let seekInFlightSeconds: Double = 3
    /// How far past the jumped-to marker's start the playhead may be and still count as "just
    /// landed there": covers a keyframe landing several seconds late plus a few seconds of
    /// watching. A keyframe may also land up to `earlyLandingSeconds` before the start.
    static let landedWindowSeconds: Double = 15
    static let earlyLandingSeconds: Double = 5
    /// Without a fresh jump: within this many seconds after a marker's start Previous goes to
    /// the marker before it, later it restarts the current one.
    static let previousRestartSlack: Double = 3

    static func targets(starts: [Double], playhead: Double, jump: Jump?, now: Date = Date()) -> Targets {
        if let jump, starts.indices.contains(jump.index) {
            let start = starts[jump.index]
            // The window ends early at the next marker: past it the user has watched into it.
            let nextStart = jump.index + 1 < starts.count ? starts[jump.index + 1] : .greatestFiniteMagnitude
            let windowEnd = min(start + landedWindowSeconds, nextStart)
            let inFlight = now.timeIntervalSince(jump.at) < seekInFlightSeconds
            let nearJumpedMarker = playhead >= start - earlyLandingSeconds && playhead < windowEnd
            if inFlight || nearJumpedMarker {
                return Targets(previous: jump.index > 0 ? jump.index - 1 : nil,
                               next: jump.index + 1 < starts.count ? jump.index + 1 : nil)
            }
        }
        return Targets(previous: starts.lastIndex { $0 < playhead - previousRestartSlack },
                       next: starts.firstIndex { $0 > playhead + 0.5 })
    }
}
