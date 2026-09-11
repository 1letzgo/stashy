//
//  PlayerMenuButton.swift
//  stashy
//
//  Das "…"-Menü des Players als UIKit-Menü. Grund: die Player-Oberfläche ist ein ZStack
//  über einem UIKit-gehosteten Video-Layer mit Tap-Regionen, Doppeltipp-Gesten und einer
//  Auto-Hide-Schicht (`opacity` + `allowsHitTesting`). SwiftUI-`Menu`s, die aus diesem
//  Stack präsentiert werden, öffnen zwar, nehmen auf echten Geräten aber keine Taps mehr
//  entgegen (dasselbe Problem hatte schon der Speed-`Picker`). Ein `UIButton` mit
//  `showsMenuAsPrimaryAction` fährt sein `UIMenu` über eine eigene
//  `UIContextMenuInteraction` und hängt damit nicht am SwiftUI-Gesture-Stack.
//

#if !os(tvOS)

import SwiftUI
import UIKit

// MARK: - Model

/// Eine Zeile im Player-Menü. Bewusst datengetrieben statt `@ViewBuilder`, damit sowohl der
/// Player selbst als auch die Hosts (`ScenePlayerExtrasController`) Zeilen liefern können,
/// ohne dass daraus SwiftUI-Views werden.
struct PlayerMenuItem: Identifiable {
    enum Kind {
        /// Normale Aktionszeile.
        case action(() -> Void)
        /// Untermenü; die Kinder dürfen selbst wieder `sectionBreak`s enthalten.
        case submenu([PlayerMenuItem])
        /// Reine Infozeile (deaktiviert, nicht auswählbar).
        case info
        /// Trenner zwischen zwei Gruppen. Ein nicht-leerer `title` wird zur Überschrift der
        /// *folgenden* Gruppe.
        case sectionBreak
    }

    let id: String
    var title: String
    var systemImage: String?
    var isChecked: Bool = false
    var isDisabled: Bool = false
    var kind: Kind
}

extension PlayerMenuItem {
    static func action(
        id: String,
        title: String,
        systemImage: String? = nil,
        isChecked: Bool = false,
        isDisabled: Bool = false,
        handler: @escaping () -> Void
    ) -> PlayerMenuItem {
        PlayerMenuItem(id: id, title: title, systemImage: systemImage,
                       isChecked: isChecked, isDisabled: isDisabled, kind: .action(handler))
    }

    static func submenu(
        id: String,
        title: String,
        systemImage: String? = nil,
        isDisabled: Bool = false,
        items: [PlayerMenuItem]
    ) -> PlayerMenuItem {
        PlayerMenuItem(id: id, title: title, systemImage: systemImage,
                       isChecked: false, isDisabled: isDisabled, kind: .submenu(items))
    }

    static func info(id: String, title: String, systemImage: String? = nil) -> PlayerMenuItem {
        PlayerMenuItem(id: id, title: title, systemImage: systemImage,
                       isChecked: false, isDisabled: true, kind: .info)
    }

    /// Trenner; `title` (optional) ist die Überschrift der Gruppe dahinter.
    static func separator(id: String, title: String = "") -> PlayerMenuItem {
        PlayerMenuItem(id: id, title: title, systemImage: nil,
                       isChecked: false, isDisabled: false, kind: .sectionBreak)
    }

    var isSectionBreak: Bool {
        if case .sectionBreak = kind { return true }
        return false
    }

    /// Alles, was das gerenderte `UIMenu` beeinflusst — ohne die Closures. Der Player
    /// rebuildet seinen Body im Sekundentakt (Spielzeit), das Menü darf davon nichts merken.
    var signature: String {
        var parts = [id, title, systemImage ?? "", isChecked ? "1" : "0", isDisabled ? "1" : "0"]
        switch kind {
        case .action: parts.append("a")
        case .info: parts.append("i")
        case .sectionBreak: parts.append("b")
        case .submenu(let nested):
            parts.append("s(" + nested.map(\.signature).joined(separator: ",") + ")")
        }
        return parts.joined(separator: "|")
    }
}

extension Array where Element == PlayerMenuItem {
    var menuSignature: String { map(\.signature).joined(separator: ";") }
}

// MARK: - UIMenu building

enum PlayerMenuBuilder {

    private struct Group {
        var title: String
        var items: [PlayerMenuItem]
    }

    /// Gruppen zwischen den `sectionBreak`s werden zu inline dargestellten `UIMenu`s — das ist
    /// die UIKit-Entsprechung von SwiftUIs `Section` und zeichnet die Trennlinie.
    private static func groups(from items: [PlayerMenuItem]) -> [Group] {
        var result: [Group] = []
        var current = Group(title: "", items: [])
        for item in items {
            if item.isSectionBreak {
                if !current.items.isEmpty { result.append(current) }
                current = Group(title: item.title, items: [])
            } else {
                current.items.append(item)
            }
        }
        if !current.items.isEmpty { result.append(current) }
        return result
    }

    static func children(from items: [PlayerMenuItem]) -> [UIMenuElement] {
        groups(from: items).map { group in
            UIMenu(title: group.title,
                   options: .displayInline,
                   children: group.items.map(element(for:)))
        }
    }

    static func menu(from items: [PlayerMenuItem]) -> UIMenu {
        UIMenu(title: "", children: children(from: items))
    }

    private static func element(for item: PlayerMenuItem) -> UIMenuElement {
        let image = item.systemImage.flatMap { UIImage(systemName: $0) }
        switch item.kind {
        case .submenu(let nested):
            return UIMenu(title: item.title,
                          image: image,
                          options: [],
                          children: children(from: nested))
        case .action(let handler):
            let action = UIAction(title: item.title, image: image) { _ in handler() }
            action.state = item.isChecked ? .on : .off
            if item.isDisabled { action.attributes.insert(.disabled) }
            return action
        case .info:
            let action = UIAction(title: item.title, image: image, attributes: .disabled) { _ in }
            action.state = item.isChecked ? .on : .off
            return action
        case .sectionBreak:
            return UIMenu(title: item.title, options: .displayInline, children: [])
        }
    }
}

// MARK: - Button

/// Transparenter `UIButton` über dem SwiftUI-Glyph: er trägt das Menü, der Glyph nur das
/// Aussehen. Die Trefferfläche ist exakt der Frame, den SwiftUI der Repräsentation gibt.
struct PlayerMenuButton: UIViewRepresentable {
    var items: [PlayerMenuItem]
    /// Wird beim Antippen und beim Öffnen gerufen — der Host hält damit die Controls offen.
    var onWillPresent: () -> Void
    /// Wird beim Schließen gerufen — der Host startet den Auto-Hide-Timer neu.
    var onDidDismiss: () -> Void
    var accessibilityTitle: String = "More options"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIButton {
        let button = MenuHostButton(type: .system)
        button.coordinator = context.coordinator
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        button.backgroundColor = .clear
        button.tintColor = .clear
        button.setTitle(nil, for: .normal)
        button.isAccessibilityElement = true
        button.accessibilityLabel = accessibilityTitle
        button.accessibilityTraits = .button
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.addTarget(context.coordinator, action: #selector(Coordinator.touchDown), for: .touchDown)
        button.addTarget(context.coordinator, action: #selector(Coordinator.touchDown), for: .menuActionTriggered)
        context.coordinator.appliedSignature = items.menuSignature
        button.menu = PlayerMenuBuilder.menu(from: items)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        (button as? MenuHostButton)?.coordinator = context.coordinator
        button.accessibilityLabel = accessibilityTitle
        // Nur bei echter Änderung neu bauen: ein Austausch von `menu` zwischen Touch-Down
        // und Touch-Up bricht die Primäraktion ab — und der Player rebuildet dauernd.
        let signature = items.menuSignature
        guard signature != context.coordinator.appliedSignature else { return }
        // Solange das Menü offen ist, wird `menu` nicht ersetzt: UIKit schließt ein
        // präsentiertes Menü, sobald man es unter ihm austauscht.
        guard !context.coordinator.isMenuVisible else {
            context.coordinator.pendingItems = items
            return
        }
        context.coordinator.appliedSignature = signature
        button.menu = PlayerMenuBuilder.menu(from: items)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PlayerMenuButton
        var isMenuVisible = false
        var pendingItems: [PlayerMenuItem]?
        var appliedSignature = ""

        init(_ parent: PlayerMenuButton) {
            self.parent = parent
        }

        @objc func touchDown() {
            parent.onWillPresent()
        }

        func menuWillDisplay() {
            isMenuVisible = true
            parent.onWillPresent()
        }

        func menuWillEnd(on button: UIButton) {
            isMenuVisible = false
            parent.onDidDismiss()
            if let pendingItems {
                self.pendingItems = nil
                appliedSignature = pendingItems.menuSignature
                button.menu = PlayerMenuBuilder.menu(from: pendingItems)
            }
        }
    }

    /// `UIButton` erfüllt selbst `UIContextMenuInteractionDelegate`; die beiden Hooks sagen
    /// dem Host, wann das Menü oben ist, damit der Auto-Hide-Timer solange ruht.
    private final class MenuHostButton: UIButton {
        weak var coordinator: Coordinator?

        override func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willDisplayMenuFor configuration: UIContextMenuConfiguration,
            animator: UIContextMenuInteractionAnimating?
        ) {
            super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
            coordinator?.menuWillDisplay()
        }

        override func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willEndFor configuration: UIContextMenuConfiguration,
            animator: UIContextMenuInteractionAnimating?
        ) {
            super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
            let coordinator = self.coordinator
            // Erst nach dem Teardown melden, sonst läuft der Reveal in die Dismiss-Animation.
            animator?.addCompletion { [weak self] in
                guard let self else { return }
                coordinator?.menuWillEnd(on: self)
            }
            if animator == nil {
                coordinator?.menuWillEnd(on: self)
            }
        }
    }
}

#endif
