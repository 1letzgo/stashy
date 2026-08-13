#if !os(tvOS)
import UIKit
import SwiftUI
import Combine

enum StashyAppIcon: String, CaseIterable, Identifiable {
    case systemDefault
    case light
    case brown
    case blue
    case purple
    case pink
    case rainbow
    case gold

    var id: String { rawValue }

    var label: String {
        switch self {
        case .systemDefault: return "Default"
        case .light: return "Light"
        case .brown: return "Brown"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .rainbow: return "Rainbow"
        case .gold: return "Gold"
        }
    }

    /// `nil` restores the primary catalog icon.
    var alternateIconName: String? {
        switch self {
        case .systemDefault: return nil
        case .light: return "AppIconLight"
        case .brown: return "AppIconBrown"
        case .blue: return "AppIconBlue"
        case .purple: return "AppIconPurple"
        case .pink: return "AppIconPink"
        case .rainbow: return "AppIconGreen"
        case .gold: return "AppIconGold"
        }
    }

    var previewAssetName: String {
        switch self {
        case .systemDefault: return "AppIconChoiceDefault"
        case .light: return "AppIconChoiceLight"
        case .brown: return "AppIconChoiceBrown"
        case .blue: return "AppIconChoiceBlue"
        case .purple: return "AppIconChoicePurple"
        case .pink: return "AppIconChoicePink"
        case .rainbow: return "AppIconChoiceGreen"
        case .gold: return "AppIconChoiceGold"
        }
    }

    static func matching(alternateIconName: String?) -> StashyAppIcon {
        allCases.first { $0.alternateIconName == alternateIconName } ?? .systemDefault
    }
}

@MainActor
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    @Published private(set) var current: StashyAppIcon

    private var cancellables = Set<AnyCancellable>()

    private init() {
        current = StashyAppIcon.matching(alternateIconName: UIApplication.shared.alternateIconName)
        StashyPlusManager.shared.$isUnlocked
            .receive(on: RunLoop.main)
            .sink { [weak self] unlocked in
                if !unlocked {
                    self?.revertToDefaultIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    func select(_ icon: StashyAppIcon) {
        guard StashyPlusManager.isUnlockedNow else {
            ToastManager.shared.show(
                "Custom app icons are part of stashy+. Unlock in Settings",
                icon: "sparkles",
                style: .error
            )
            return
        }
        apply(icon)
    }

    func revertToDefaultIfNeeded() {
        guard current != .systemDefault || UIApplication.shared.alternateIconName != nil else { return }
        apply(.systemDefault)
    }

    private func apply(_ icon: StashyAppIcon) {
        let name = icon.alternateIconName
        guard UIApplication.shared.alternateIconName != name else {
            current = icon
            return
        }
        guard UIApplication.shared.supportsAlternateIcons else {
            ToastManager.shared.show("This device cannot change the app icon", icon: "info.circle", style: .info)
            return
        }
        // Hop off the SwiftUI Form/chrome presenter so Apple's confirmation
        // is a normal window alert (English via CFBundleLocalizations).
        DispatchQueue.main.async {
            Self.prepareKeyWindowForSystemAlert()
            UIApplication.shared.setAlternateIconName(name) { [weak self] error in
                DispatchQueue.main.async {
                    if let error {
                        ToastManager.shared.show(error.localizedDescription, icon: "exclamationmark.triangle", style: .error)
                    } else {
                        self?.current = icon
                    }
                }
            }
        }
    }

    private static func prepareKeyWindowForSystemAlert() {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first else { return }
        window.endEditing(true)
        window.makeKeyAndVisible()
        window.rootViewController?.view.becomeFirstResponder()
    }
}

struct StashyPlusAppIconSettings: View {
    @ObservedObject private var icons = AppIconManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(StashyAppIcon.allCases) { icon in
                iconCell(icon)
            }
        }
        .padding(.vertical, 8)
    }

    private func iconCell(_ icon: StashyAppIcon) -> some View {
        let selected = icons.current == icon
        return VStack(spacing: 6) {
            Image(icon.previewAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            selected ? appearanceManager.tintColor : Color.primary.opacity(0.2),
                            lineWidth: selected ? 2.5 : 1
                        )
                )
            Text(icon.label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .onTapGesture {
            HapticManager.selection()
            icons.select(icon)
        }
        .accessibilityLabel(icon.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif
