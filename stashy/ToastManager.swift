//
//  ToastManager.swift
//  stashy
//
//  Created by Daniel Goletz on 07.02.26.
//

import SwiftUI

// MARK: - Toast Manager

class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var currentToast: ToastMessage?

    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String, icon: String = "checkmark.circle.fill", style: ToastStyle = .success, duration: TimeInterval = 2.0) {
        dismissTask?.cancel()

        withAnimation(DesignTokens.Animation.spring) {
            currentToast = ToastMessage(message: message, icon: icon, style: style)
        }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(DesignTokens.Animation.standard) {
                currentToast = nil
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(DesignTokens.Animation.standard) {
            currentToast = nil
        }
    }
}

// MARK: - Toast Message

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let icon: String
    let style: ToastStyle

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

enum ToastStyle {
    case success
    case error
    case info

    var iconColor: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .foregroundColor(toast.style.iconColor)
                .font(.system(size: 16, weight: .semibold))

            Text(toast.message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .cardShadow()
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Toast View Modifier

struct ToastModifier: ViewModifier {
    @ObservedObject var toastManager = ToastManager.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toastManager.currentToast {
                    ToastView(toast: toast)
                        .padding(.top, 8)
                        .zIndex(999)
                }
            }
    }
}

extension View {
    func withToasts() -> some View {
        self.modifier(ToastModifier())
    }
}
