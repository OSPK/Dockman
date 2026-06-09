import AppKit
import ConfigKit

/// The menu-bar item — Dockman's only always-visible system UI in Phase 1.
/// Drives all Dock management until the SwiftUI settings window arrives (Phase 4).
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: DockmanController
    private let targeting = DockTargetingController()
    private let settingsWindow = SettingsWindowController()

    init(controller: DockmanController) {
        self.controller = controller
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.stack.fill", accessibilityDescription: "Dockman")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    // Rebuilt each time the menu opens so it always reflects current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let currentSpace = controller.monitor.topology.displays.first?.currentSpace?.id ?? 0
        let header = NSMenuItem(title: "Current desktop: Space \(currentSpace)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if controller.config.docks.isEmpty {
            let empty = NSMenuItem(title: "No docks yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for dock in controller.config.docks {
            let orphaned = controller.orphanedDockIDs.contains(dock.id)
            let suffix = !dock.enabled ? "  (disabled)"
                       : orphaned ? "  ⚠ desktop removed"
                       : ""
            let title = "\(orphaned ? "⚠ " : "")\(dock.name)  —  \(Self.describe(dock.binding))\(suffix)"
            let dockItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            dockItem.submenu = makeDockSubmenu(for: dock, orphaned: orphaned)
            menu.addItem(dockItem)
        }

        menu.addItem(.separator())
        addItem(to: menu, title: "Settings…", key: ",", action: #selector(openSettings))
        addItem(to: menu, title: "New Dock on This Desktop", key: "n", action: #selector(newDock))
        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = controller.isLoginItemEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        addItem(to: menu, title: "Quit Dockman", key: "q", action: #selector(quit))
    }

    private func makeDockSubmenu(for dock: DockModel, orphaned: Bool) -> NSMenu {
        let sub = NSMenu()

        if orphaned {
            let warn = NSMenuItem(title: "The desktop this dock was pinned to was removed.",
                                  action: nil, keyEquivalent: "")
            warn.isEnabled = false
            sub.addItem(warn)
            let fix = NSMenuItem(title: "Re-pin to This Desktop", action: #selector(pinDock(_:)), keyEquivalent: "")
            fix.target = self
            fix.representedObject = dock.id
            sub.addItem(fix)
            sub.addItem(.separator())
        }

        let toggle = NSMenuItem(title: dock.enabled ? "Enabled" : "Enable",
                                action: #selector(toggleDock(_:)), keyEquivalent: "")
        toggle.state = dock.enabled ? .on : .off
        toggle.target = self
        toggle.representedObject = dock.id
        sub.addItem(toggle)

        sub.addItem(.separator())

        // The rich spatial picker (docs/09) — move to any monitor/desktop.
        let move = NSMenuItem(title: "Move Dock…", action: #selector(moveDock(_:)), keyEquivalent: "")
        move.target = self
        move.representedObject = dock.id
        sub.addItem(move)

        let pin = NSMenuItem(title: "Quick: Pin to This Desktop", action: #selector(pinDock(_:)), keyEquivalent: "")
        pin.target = self
        pin.representedObject = dock.id
        sub.addItem(pin)

        let all = NSMenuItem(title: "Show on All Desktops", action: #selector(allSpaces(_:)), keyEquivalent: "")
        all.target = self
        all.representedObject = dock.id
        all.state = dock.binding.mode == .allSpaces ? .on : .off
        sub.addItem(all)

        sub.addItem(.separator())

        // Auto-hide toggle (docs/04 §4.5).
        let autoHide = NSMenuItem(title: "Auto-hide", action: #selector(toggleAutoHide(_:)), keyEquivalent: "")
        autoHide.target = self
        autoHide.representedObject = dock.id
        autoHide.state = dock.behavior.autoHide ? .on : .off
        sub.addItem(autoHide)

        // Summon clicked app windows onto this Dock's screen (needs Accessibility).
        let summon = NSMenuItem(title: "Summon Windows to This Screen", action: #selector(toggleSummon(_:)), keyEquivalent: "")
        summon.target = self
        summon.representedObject = dock.id
        summon.state = dock.behavior.summonWindows ? .on : .off
        sub.addItem(summon)

        // Style submenu (background treatment).
        let styleItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for style in [Appearance.Style.liquidGlass, .classic, .solid, .minimal] {
            let option = NSMenuItem(title: style.displayName, action: #selector(setStyle(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = dock.id
            option.tag = styleOrder.firstIndex(of: style) ?? 0
            option.state = dock.appearance.style == style ? .on : .off
            styleMenu.addItem(option)
        }
        styleItem.submenu = styleMenu
        sub.addItem(styleItem)

        // Position submenu (which screen edge the Dock sits on).
        let posItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let posMenu = NSMenu()
        let edges: [(String, Appearance.Edge)] = [("Bottom", .bottom), ("Top", .top), ("Left", .left), ("Right", .right)]
        for (index, (label, edge)) in edges.enumerated() {
            let option = NSMenuItem(title: label, action: #selector(setEdge(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = dock.id
            option.tag = index
            option.state = dock.appearance.edge == edge ? .on : .off
            posMenu.addItem(option)
        }
        posItem.submenu = posMenu
        sub.addItem(posItem)

        // Icon size submenu.
        let sizeItem = NSMenuItem(title: "Icon Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (label, value) in [("Small", 36.0), ("Medium", 52.0), ("Large", 72.0), ("Huge", 96.0)] {
            let option = NSMenuItem(title: label, action: #selector(setIconSize(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = dock.id
            option.tag = Int(value)
            option.state = abs(dock.appearance.iconSize - value) < 0.5 ? .on : .off
            sizeMenu.addItem(option)
        }
        sizeItem.submenu = sizeMenu
        sub.addItem(sizeItem)

        sub.addItem(.separator())

        let del = NSMenuItem(title: "Delete Dock", action: #selector(deleteDock(_:)), keyEquivalent: "")
        del.target = self
        del.representedObject = dock.id
        sub.addItem(del)

        return sub
    }

    private func addItem(to menu: NSMenu, title: String, key: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    static func describe(_ binding: Binding) -> String {
        switch binding.mode {
        case .allSpaces:
            return "all desktops"
        case .spaces:
            if let id = binding.spaces.first?.spaceID { return "Space \(id)" }
            return "unpinned"
        }
    }

    // MARK: - Actions

    @objc private func moveDock(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let button = item.button else { return }
        // Show the popover just after the menu finishes closing.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.targeting.present(dockID: id, controller: self.controller, from: button)
        }
    }

    @objc private func toggleDock(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { controller.toggleDock(id) }
    }
    @objc private func pinDock(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { controller.pinDockHere(id) }
    }
    @objc private func allSpaces(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { controller.setDockAllSpaces(id) }
    }
    @objc private func toggleAutoHide(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { controller.setAutoHide(id, sender.state != .on) }
    }
    @objc private func toggleSummon(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { controller.setSummonWindows(id, sender.state != .on) }
    }
    @objc private func setIconSize(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { controller.setIconSize(id, Double(sender.tag)) }
    }
    private let edgeOrder: [Appearance.Edge] = [.bottom, .top, .left, .right]
    @objc private func setEdge(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, edgeOrder.indices.contains(sender.tag) else { return }
        controller.setEdge(id, edgeOrder[sender.tag])
    }
    private let styleOrder: [Appearance.Style] = [.liquidGlass, .classic, .solid, .minimal]
    @objc private func setStyle(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, styleOrder.indices.contains(sender.tag) else { return }
        controller.setStyle(id, styleOrder[sender.tag])
    }
    @objc private func deleteDock(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { controller.deleteDock(id) }
    }
    @objc private func newDock() { controller.newDockHere() }
    @objc private func openSettings() { settingsWindow.show(controller: controller) }
    @objc private func toggleLogin() { controller.toggleLaunchAtLogin() }
    @objc private func quit() { NSApp.terminate(nil) }
}
