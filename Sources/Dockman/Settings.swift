import AppKit
import SwiftUI
import ConfigKit
import DockKit

private enum SettingsTab: Hashable {
    case general
    case dock(UUID)
}

extension Color {
    init?(dockHex hex: String) {
        guard let ns = NSColor(hex: hex) else { return nil }
        self = Color(nsColor: ns)
    }
}

// MARK: - Root

struct SettingsRootView: View {
    @ObservedObject var controller: DockmanController
    @State private var selection: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Docks") {
                    ForEach(controller.config.docks) { dock in
                        Label(dock.name, systemImage: dock.enabled ? "rectangle.stack.fill" : "rectangle.stack")
                            .tag(SettingsTab.dock(dock.id))
                    }
                }
                Section {
                    Label("General", systemImage: "gearshape").tag(SettingsTab.general)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                Button {
                    controller.newDockHere()
                } label: { Image(systemName: "plus") }
                .help("Add a dock on the current desktop")
            }
        } detail: {
            switch selection {
            case .general:
                GeneralSettingsView(controller: controller)
            case .dock(let id):
                if controller.config.docks.contains(where: { $0.id == id }) {
                    DockSettingsView(controller: controller, dockID: id)
                } else {
                    ContentUnavailableViewCompat(text: "Dock removed")
                }
            }
        }
        .frame(minWidth: 660, minHeight: 500)
    }
}

// MARK: - Per-dock

struct DockSettingsView: View {
    @ObservedObject var controller: DockmanController
    let dockID: UUID

    private let tints: [(String, String?)] = [
        ("Default", nil), ("Blue", "#0A84FF"), ("Purple", "#BF5AF2"),
        ("Pink", "#FF375F"), ("Orange", "#FF9F0A"), ("Green", "#30D158"), ("Gray", "#8E8E93"),
    ]

    var body: some View {
        if let dock = controller.dock(dockID) {
            Form {
                Section("Dock") {
                    TextField("Name", text: Binding(
                        get: { dock.name }, set: { controller.renameDock(dockID, $0) }))
                    Toggle("Enabled", isOn: Binding(
                        get: { dock.enabled }, set: { controller.setEnabled(dockID, $0) }))
                }

                Section("Appearance") {
                    Picker("Style", selection: Binding(
                        get: { dock.appearance.style }, set: { controller.setStyle(dockID, $0) })) {
                        ForEach([Appearance.Style.liquidGlass, .classic, .solid, .minimal], id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    Picker("Position", selection: Binding(
                        get: { dock.appearance.edge }, set: { controller.setEdge(dockID, $0) })) {
                        Text("Bottom").tag(Appearance.Edge.bottom)
                        Text("Top").tag(Appearance.Edge.top)
                        Text("Left").tag(Appearance.Edge.left)
                        Text("Right").tag(Appearance.Edge.right)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading) {
                        LabeledContent("Icon Size", value: "\(Int(dock.appearance.iconSize)) px")
                        Slider(value: Binding(
                            get: { dock.appearance.iconSize },
                            set: { controller.setIconSize(dockID, $0) }), in: 24...128, step: 4)
                    }

                    Toggle("Magnification", isOn: Binding(
                        get: { dock.appearance.magnification },
                        set: { controller.setMagnification(dockID, $0) }))

                    VStack(alignment: .leading) {
                        LabeledContent("Margin", value: "\(Int(dock.appearance.padding)) px")
                        Slider(value: Binding(
                            get: { dock.appearance.padding },
                            set: { controller.setPadding(dockID, $0) }), in: 0...32, step: 2)
                    }
                    .help("Space between the icons and the edge of the bar")

                    VStack(alignment: .leading) {
                        LabeledContent("Screen Edge Gap", value: "\(Int(dock.appearance.edgeGap)) px")
                        Slider(value: Binding(
                            get: { dock.appearance.edgeGap },
                            set: { controller.setEdgeGap(dockID, $0) }), in: 0...64, step: 2)
                    }
                    .help("Distance between the bar and the edge of the screen (0 = flush)")

                    HStack {
                        Text("Tint")
                        Spacer()
                        ForEach(tints, id: \.0) { name, hex in
                            Circle()
                                .fill(hex.flatMap { Color(dockHex: $0) } ?? Color.secondary.opacity(0.25))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(dock.appearance.tintHex == hex ? Color.primary : .clear, lineWidth: 2))
                                .onTapGesture { controller.setTint(dockID, hex) }
                                .help(name)
                        }
                    }
                }

                Section("Behavior") {
                    Toggle("Auto-hide", isOn: Binding(
                        get: { dock.behavior.autoHide }, set: { controller.setAutoHide(dockID, $0) }))
                    Toggle("Summon windows to this screen", isOn: Binding(
                        get: { dock.behavior.summonWindows }, set: { controller.setSummonWindows(dockID, $0) }))
                    Toggle("Show over fullscreen apps", isOn: Binding(
                        get: { dock.behavior.showOverFullscreen }, set: { controller.setShowOverFullscreen(dockID, $0) }))
                }

                Section("Placement") {
                    Text(placementSummary(dock)).foregroundStyle(.secondary)
                    HStack {
                        Button("Pin to Current Desktop") { controller.pinDockHere(dockID) }
                        Button("Show on All Desktops") { controller.setDockAllSpaces(dockID) }
                    }
                }

                Section {
                    Button("Delete Dock", role: .destructive) { controller.deleteDock(dockID) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(dock.name)
        }
    }

    private func placementSummary(_ dock: DockModel) -> String {
        switch dock.binding.mode {
        case .allSpaces: return "Shown on all desktops."
        case .spaces:
            if let id = dock.binding.spaces.first?.spaceID { return "Pinned to desktop (Space \(id))." }
            return "Not pinned."
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var controller: DockmanController

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Start at Login", isOn: Binding(
                    get: { controller.isLoginItemEnabled },
                    set: { _ in controller.toggleLaunchAtLogin() }))
            }
            Section("System Dock") {
                Toggle("Hide the built-in macOS Dock", isOn: Binding(
                    get: { controller.config.global.hideSystemDock },
                    set: { controller.setHideSystemDock($0) }))
                Text("Restored automatically when turned off.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Docks") {
                Button("Add Dock on Current Desktop") { controller.newDockHere() }
            }
            Section("About") {
                LabeledContent("Version", value: appVersion())
                LabeledContent("Scripting", value: "dockman://toggle?dock=Name")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private func appVersion() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

/// Tiny fallback so we don't depend on macOS 14-only ContentUnavailableView.
private struct ContentUnavailableViewCompat: View {
    let text: String
    var body: some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Hosting window

final class SettingsWindowController {
    private var window: NSWindow?

    func show(controller: DockmanController) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsRootView(controller: controller))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Dockman Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.setContentSize(NSSize(width: 700, height: 540))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
