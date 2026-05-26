import SwiftUI

struct TVStarRatingPill: View {
    let rating100: Int?
    let onRatingCommitted: (Int?) -> Void

    @State private var isEditing = false
    @State private var editingStars: Int = 0
    @State private var isFocused = false

    private var currentStars: Int {
        guard let r = rating100 else { return 0 }
        return min(5, max(0, Int(round(Double(r) / 20.0))))
    }

    private var displayStars: Int {
        isEditing ? editingStars : currentStars
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= displayStars ? "star.fill" : "star")
                    .font(.headline)
                    .foregroundColor(index <= displayStars ? .yellow : .gray.opacity(0.4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isEditing ? Color.yellow.opacity(0.2) :
                (isFocused ? Color.white.opacity(0.15) : Color.white.opacity(0.06))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isEditing ? Color.yellow.opacity(0.8) : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        .animation(.easeInOut(duration: 0.2), value: isEditing)
        .animation(.easeInOut(duration: 0.15), value: displayStars)
        .overlay {
            RatingFocusInputView(
                onToggleEdit: { nowEditing in
                    if nowEditing {
                        editingStars = currentStars
                        isEditing = true
                    } else {
                        let newRating = editingStars == 0 ? nil : editingStars * 20
                        onRatingCommitted(newRating)
                        isEditing = false
                    }
                },
                onAdjustStars: { delta in
                    editingStars = min(5, max(0, editingStars + delta))
                },
                onFocusChange: { focused in
                    isFocused = focused
                    if !focused && isEditing {
                        let newRating = editingStars == 0 ? nil : editingStars * 20
                        onRatingCommitted(newRating)
                        isEditing = false
                    }
                }
            )
        }
    }
}

// MARK: - UIKit focus view for D-pad input

private struct RatingFocusInputView: UIViewRepresentable {
    var onToggleEdit: (Bool) -> Void
    var onAdjustStars: (Int) -> Void
    var onFocusChange: (Bool) -> Void

    func makeUIView(context: Context) -> RatingFocusUIView {
        let view = RatingFocusUIView()
        view.backgroundColor = .clear
        view.onToggleEdit = onToggleEdit
        view.onAdjustStars = onAdjustStars
        view.onFocusChange = onFocusChange
        return view
    }

    func updateUIView(_ uiView: RatingFocusUIView, context: Context) {
        uiView.onToggleEdit = onToggleEdit
        uiView.onAdjustStars = onAdjustStars
        uiView.onFocusChange = onFocusChange
    }
}

private final class RatingFocusUIView: UIView {
    var isEditing = false
    var onToggleEdit: ((Bool) -> Void)?
    var onAdjustStars: ((Int) -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    override var canBecomeFocused: Bool { true }

    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        guard isEditing else { return super.shouldUpdateFocus(in: context) }
        let heading = context.focusHeading
        if heading.contains(.up) || heading.contains(.down) {
            isEditing = false
            return true
        }
        return false
    }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        let focused = isFocused
        if !focused { isEditing = false }
        onFocusChange?(focused)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first else {
            super.pressesBegan(presses, with: event)
            return
        }
        switch press.type {
        case .select:
            isEditing.toggle()
            onToggleEdit?(isEditing)
        case .leftArrow where isEditing:
            onAdjustStars?(-1)
        case .rightArrow where isEditing:
            onAdjustStars?(1)
        default:
            super.pressesBegan(presses, with: event)
        }
    }
}
