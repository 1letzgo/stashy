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
    /// The menu stays open after this action; it updates in place instead (e.g. expanding or
    /// collapsing a picker inside a submenu).
    var keepsMenuOpen: Bool = false
    var kind: Kind
}

extension PlayerMenuItem {
    static func action(
        id: String,
        title: String,
        systemImage: String? = nil,
        isChecked: Bool = false,
        isDisabled: Bool = false,
        keepsMenuOpen: Bool = false,
        handler: @escaping () -> Void
    ) -> PlayerMenuItem {
        PlayerMenuItem(id: id, title: title, systemImage: systemImage,
                       isChecked: isChecked, isDisabled: isDisabled,
                       keepsMenuOpen: keepsMenuOpen, kind: .action(handler))
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
        var parts = [id, title, systemImage ?? "", isChecked ? "1" : "0", isDisabled ? "1" : "0",
                     keepsMenuOpen ? "k" : ""]
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

    static let rootIdentifier = UIMenu.Identifier("stashy.player.menu.root")

    static func menu(from items: [PlayerMenuItem]) -> UIMenu {
        UIMenu(title: "", identifier: rootIdentifier, children: children(from: items))
    }

    /// The open menu level updated from fresh items: the root, or the submenu with the same id.
    /// Used while the menu is on screen, so state changes show without closing it.
    ///
    /// UIKit hands every displayed level to the update block, root first. A level whose own rows
    /// did not change is returned as it is — rebuilding the root would swap out the submenu the
    /// user is looking at, and on device the old one then stays on screen. A changed level keeps
    /// its identity and only gets new children.
    static func refreshed(_ visible: UIMenu, from items: [PlayerMenuItem], previous: [PlayerMenuItem]) -> UIMenu {
        let level: (new: [PlayerMenuItem], old: [PlayerMenuItem])?
        if visible.identifier == rootIdentifier {
            level = (items, previous)
        } else if case .submenu(let nested)? = submenuItem(id: visible.identifier.rawValue, in: items)?.kind {
            let old: [PlayerMenuItem]
            if case .submenu(let oldNested)? = submenuItem(id: visible.identifier.rawValue, in: previous)?.kind {
                old = oldNested
            } else {
                old = []
            }
            level = (nested, old)
        } else {
            level = nil
        }
        guard let level, levelSignature(level.new) != levelSignature(level.old) else { return visible }
        return visible.replacingChildren(children(from: level.new))
    }

    /// What one menu level shows itself: its rows, and for submenus only their title line — a
    /// change deeper down belongs to that submenu's own level.
    private static func levelSignature(_ items: [PlayerMenuItem]) -> String {
        items.map { item in
            if case .submenu = item.kind {
                return [item.id, item.title, item.systemImage ?? "", item.isDisabled ? "1" : "0", "s"]
                    .joined(separator: "|")
            }
            return item.signature
        }
        .joined(separator: ";")
    }

    private static func submenuItem(id: String, in items: [PlayerMenuItem]) -> PlayerMenuItem? {
        for item in items {
            guard case .submenu(let nested) = item.kind else { continue }
            if item.id == id { return item }
            if let found = submenuItem(id: id, in: nested) { return found }
        }
        return nil
    }

    private static func element(for item: PlayerMenuItem) -> UIMenuElement {
        let image = item.systemImage.flatMap { UIImage(systemName: $0) }
        switch item.kind {
        case .submenu(let nested):
            return UIMenu(title: item.title,
                          image: image,
                          identifier: UIMenu.Identifier(item.id),
                          options: [],
                          children: children(from: nested))
        case .action(let handler):
            let action = UIAction(title: item.title, image: image) { _ in handler() }
            action.state = item.isChecked ? .on : .off
            if item.isDisabled { action.attributes.insert(.disabled) }
            if item.keepsMenuOpen { action.attributes.insert(.keepsMenuPresented) }
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
        context.coordinator.shownItems = items
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
        // präsentiertes Menü, sobald man es unter ihm austauscht. Die sichtbare Ebene wird
        // stattdessen live aktualisiert; das volle Menü folgt beim Schließen.
        guard !context.coordinator.isMenuVisible else {
            let previous = context.coordinator.shownItems
            context.coordinator.pendingItems = items
            context.coordinator.shownItems = items
            context.coordinator.appliedSignature = signature
            let items = items
            button.contextMenuInteraction?.updateVisibleMenu { visible in
                PlayerMenuBuilder.refreshed(visible, from: items, previous: previous)
            }
            return
        }
        context.coordinator.appliedSignature = signature
        context.coordinator.shownItems = items
        button.menu = PlayerMenuBuilder.menu(from: items)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PlayerMenuButton
        var isMenuVisible = false
        var pendingItems: [PlayerMenuItem]?
        var appliedSignature = ""
        /// The rows the open menu currently shows — the baseline for in-place updates.
        var shownItems: [PlayerMenuItem] = []

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
                shownItems = pendingItems
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
