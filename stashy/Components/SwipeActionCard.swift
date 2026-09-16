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
/// cards out in `LazyVGrid`s, so the gesture is rebuilt here with the system's feel: the buttons
/// grow out of the trailing edge with the finger, the destructive one takes over the whole row on
/// a full swipe, and everything settles with a spring.
struct StashySwipeActionsModifier: ViewModifier {
    let actions: [StashySwipeAction]

    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    @State private var width: CGFloat = 0
    @State private var isFullSwipe = false
    @State private var isDeleting = false

    /// Resting width per button, as in Mail.
    private let buttonWidth: CGFloat = 76
    private var openWidth: CGFloat { buttonWidth * CGFloat(actions.count) }
    private var reveal: CGFloat { max(0, -offset) }
    private var fullSwipeThreshold: CGFloat { max(openWidth + 80, width * 0.55) }
    private var destructive: StashySwipeAction? { actions.last(where: { $0.isDestructive }) }
    private var cornerRadius: CGFloat { DesignTokens.CornerRadius.card }
    private var springOpen: Animation { .spring(response: 0.34, dampingFraction: 0.82) }
    private var springClose: Animation { .spring(response: 0.3, dampingFraction: 0.9) }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            // Sits still behind the card; only its width follows the finger.
            actionRail
            content
                .offset(x: offset)
                .highPriorityGesture(dragGesture)
                // While a row is open, a tap closes it instead of opening the card.
                .simultaneousGesture(TapGesture().onEnded { close() }, including: isOpen ? .all : .subviews)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { width = geo.size.width }
                    .onChange(of: geo.size.width) { _, new in width = new }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Buttons sized from the current drag, so they slide out of the edge with the finger.
    private var actionRail: some View {
        HStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                let share = railWidth(for: index)
                Button {
                    close()
                    action.handler()
                } label: {
                    label(for: action, width: share)
                        // The first button's extra strip hides under the card; keep its icon
                        // centred in the part the user actually sees.
                        .padding(.leading, index == 0 && !isFullSwipe ? cornerRadius : 0)
                }
                .buttonStyle(.plain)
                .frame(width: share)
                .frame(maxHeight: .infinity)
                .clipped()
            }
        }
        // Widened by the corner radius and tucked under the card: without it the card's rounded
        // trailing corner left a notch of page background between the row and the first button.
        .frame(width: reveal > 0 ? reveal + cornerRadius : 0, alignment: .trailing)
        .background(Color.appBackground)
        .opacity(reveal > 0.5 ? 1 : 0)
    }

    /// On a full swipe the destructive action swallows the other buttons' width.
    private func railWidth(for index: Int) -> CGFloat {
        guard reveal > 0 else { return 0 }
        let total = reveal + cornerRadius
        let isLast = index == actions.count - 1
        if isFullSwipe, let destructive, actions[index].id == destructive.id {
            return total
        }
        if isFullSwipe { return 0 }
        let even = reveal / CGFloat(actions.count)
        // The leftmost button carries the tuck-under strip; rounding leftovers go to the last
        // one so no hairline gap shows between the buttons.
        if index == 0 { return even + cornerRadius }
        return isLast ? total - (even + cornerRadius) - even * CGFloat(max(0, actions.count - 2)) : even
    }

    /// Tinted capsule with the caption underneath — the same shape the system draws for
    /// `.swipeActions` in Tools › Filters.
    @ViewBuilder
    private func label(for action: StashySwipeAction, width: CGFloat) -> some View {
        VStack(spacing: 6) {
            Image(systemName: action.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: min(max(width - 16, 28), 62), height: 44)
                .background(action.tint, in: Capsule())
            // The caption only appears once the button is wide enough to hold it.
            Text(action.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .opacity(width >= 62 ? 1 : 0)
                .frame(height: width >= 62 ? nil : 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                // Vertical scrolling stays with the surrounding ScrollView.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                guard !isDeleting else { return }
                let base = isOpen ? -openWidth : 0
                let proposed = base + value.translation.width
                // Rubber band past the buttons, and no swiping the card to the right.
                let resisted = proposed < -openWidth ? -openWidth + (proposed + openWidth) * 0.55 : proposed
                offset = min(0, resisted)

                let reachedFullSwipe = destructive != nil && -offset > fullSwipeThreshold
                if reachedFullSwipe != isFullSwipe {
                    withAnimation(springOpen) { isFullSwipe = reachedFullSwipe }
                    HapticManager.light()
                }
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), !isDeleting else {
                    withAnimation(springClose) { offset = isOpen ? -openWidth : 0 }
                    return
                }
                if isFullSwipe, let destructive {
                    isDeleting = true
                    HapticManager.medium()
                    withAnimation(.easeIn(duration: 0.22)) { offset = -(width + openWidth) }
                    // Let the row run off screen before the model drops it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { destructive.handler() }
                    return
                }
                // Flicking left opens even when the finger did not travel the full width.
                let flicked = value.predictedEndTranslation.width < -buttonWidth
                if -offset > buttonWidth * 0.5 || flicked {
                    if !isOpen { HapticManager.light() }
                    isOpen = true
                    withAnimation(springOpen) { offset = -openWidth }
                } else {
                    close()
                }
            }
    }

    private func close() {
        guard isOpen || offset != 0 else { return }
        isOpen = false
        isFullSwipe = false
        withAnimation(springClose) { offset = 0 }
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
