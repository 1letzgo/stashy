import SwiftUI

struct TVOCountPill: View {
    let oCounter: Int?
    let iconName: String
    let onIncrement: () -> Void

    @State private var isFocused = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundColor(.red)
            Text("\(oCounter ?? 0)")
        }
        .font(.headline)
        .foregroundColor(.white.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isFocused ? Color.white.opacity(0.15) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        .overlay {
            OCountFocusInputView(
                isFocused: $isFocused,
                onSelect: onIncrement
            )
        }
    }
}

// MARK: - UIKit focus view for reliable focus detection

private struct OCountFocusInputView: UIViewRepresentable {
    @Binding var isFocused: Bool
    var onSelect: () -> Void

    func makeUIView(context: Context) -> OCountFocusUIView {
        let view = OCountFocusUIView()
        view.backgroundColor = .clear
        view.onSelect = onSelect
        view.onFocusChange = { focused in
            DispatchQueue.main.async { isFocused = focused }
        }
        return view
    }

    func updateUIView(_ uiView: OCountFocusUIView, context: Context) {
        uiView.onSelect = onSelect
    }
}

private final class OCountFocusUIView: UIView {
    var onSelect: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    override var canBecomeFocused: Bool { true }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        onFocusChange?(isFocused)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first else {
            super.pressesBegan(presses, with: event)
            return
        }
        switch press.type {
        case .select:
            onSelect?()
        default:
            super.pressesBegan(presses, with: event)
        }
    }
}
