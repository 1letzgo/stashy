//
//  SwipeActionCard.swift
//  stashy
//
//  Swipe actions for cards that live in a grid or stack instead of a `List`.
//

#if !os(tvOS)
import SwiftUI

/// One button behind the card.
struct StashySwipeAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: Color
    /// The rightmost destructive action also fires on a full swipe.
    var isDestructive: Bool = false
    let handler: () -> Void
}

/// `.swipeActions` only exists inside a `List`. Downloads and the other Tools screens lay their
/// cards out in `LazyVGrid`s, so the gesture is rebuilt here: drag left to reveal the buttons,
/// keep dragging past the card's half width to fire the destructive one directly.
struct StashySwipeActionsModifier: ViewModifier {
    let actions: [StashySwipeAction]

    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    @State private var width: CGFloat = 0

    private var buttonWidth: CGFloat { 72 }
    private var openWidth: CGFloat { buttonWidth * CGFloat(actions.count) }
    /// Past this the drag completes on its own — the same feel as Mail's full swipe.
    private var fullSwipeThreshold: CGFloat { max(openWidth + 60, width * 0.5) }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            buttons
            content
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear { width = geo.size.width }
                    }
                )
                .offset(x: offset)
                .highPriorityGesture(dragGesture)
                // A tap anywhere closes an open row instead of opening the card.
                .simultaneousGesture(TapGesture().onEnded {
                    if isOpen { close() }
                }, including: isOpen ? .all : .subviews)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                Button {
                    close()
                    action.handler()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: action.systemImage)
                            .font(.title3)
                        Text(action.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .frame(width: buttonWidth)
                    .frame(maxHeight: .infinity)
                    .background(action.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(offset < -1 ? 1 : 0)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // Vertical scrolling stays with the surrounding ScrollView.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let base = isOpen ? -openWidth : 0
                let proposed = base + value.translation.width
                // Rubber band once past the buttons; no swiping the card to the right.
                offset = min(0, proposed < -openWidth ? -openWidth + (proposed + openWidth) / 3 : proposed)
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    withAnimation(.snappy) { offset = isOpen ? -openWidth : 0 }
                    return
                }
                let base = isOpen ? -openWidth : 0
                let total = base + value.translation.width
                if let destructive = actions.last(where: { $0.isDestructive }), total < -fullSwipeThreshold {
                    HapticManager.medium()
                    withAnimation(.snappy) { offset = -(width + openWidth) }
                    destructive.handler()
                    return
                }
                if total < -buttonWidth / 2 {
                    isOpen = true
                    withAnimation(.snappy) { offset = -openWidth }
                } else {
                    close()
                }
            }
    }

    private func close() {
        isOpen = false
        withAnimation(.snappy) { offset = 0 }
    }
}

extension View {
    /// Swipe-left actions for a card outside a `List`. The rightmost destructive action also
    /// fires on a full swipe.
    func stashySwipeActions(_ actions: [StashySwipeAction]) -> some View {
        modifier(StashySwipeActionsModifier(actions: actions))
    }
}
#endif
