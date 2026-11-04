//
//  FoldLayout.swift
//  stashy
//
//  The fold of the iPhone Duo's inner display: where it runs through a view, and the hinge state.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The part of a view that lies on the fold, in the view's own coordinates.
struct FoldRegion: Equatable {
    let frame: CGRect

    /// A vertical fold splits the view into a left and a right side (the usual book hold); a
    /// horizontal one into top and bottom.
    var isVertical: Bool { frame.height > frame.width }
}

extension GeometryProxy {
    /// The fold running through this view. `nil` without one: every other device, the closed
    /// iPhone Duo, and a view that lies entirely on one side.
    var foldRegion: FoldRegion? {
        #if os(iOS)
        guard #available(iOS 27.1, *) else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        // Lying flat, the system reports the fold as inactive (nothing forces content off it), so
        // inactive regions count too: layouts keep their shape while the hinge moves.
        guard let frame = reservedRegions(kind: .division, options: [.includeInactive])
            .first(where: { $0.frame.intersects(bounds) })?
            .frame else { return nil }
        return FoldRegion(frame: frame)
        #else
        return nil
        #endif
    }
}

#if os(iOS)
/// Reports whether the iPhone Duo stands half open. Stays `false` on every other device.
@available(iOS 27.1, *)
private struct HingeObserverView: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.addInteraction(UIHingeInteraction { _, update in
            onChange(update.hinge?.status == .partiallyOpen)
        })
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension View {
    /// Keeps `isPartiallyOpen` in step with the hinge.
    @ViewBuilder
    func observesHalfOpenHinge(_ isPartiallyOpen: Binding<Bool>) -> some View {
        if #available(iOS 27.1, *) {
            background(HingeObserverView { isPartiallyOpen.wrappedValue = $0 })
        } else {
            self
        }
    }
}
#endif
