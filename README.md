<p align="center">
  <img src="logo.png" alt="Dockman" width="200">
</p>

# Dockman

**Additional, fully customizable Docks for macOS — each one pinned to a specific desktop (Space).**

The built-in macOS Dock is a singleton: there is exactly one, it follows the active display, and you cannot have a different Dock per virtual desktop. Dockman lets you place one or more independent Docks and **bind each to a particular Space**, so switching desktops switches which Dock(s) you see. It works **without disabling System Integrity Protection (SIP)**, without Dock injection, and even when the system setting **"Displays have separate Spaces" is disabled**.

> Verified on **macOS 26.5 (Tahoe), Apple Silicon (arm64)**, across 3 displays. Designed to also run on macOS 14 (Sonoma) and 15 (Sequoia).

---

## Features

- **Per-desktop Docks** — bind any Dock to any Space; it appears on that desktop only, even with "Displays have separate Spaces" off.
- **Multiple Docks** — run as many as you want, each with its own items, position, and style.
- **Rich item kinds** — apps, files, folder stacks (with popovers), spacers, separators, custom actions, and a live **running-apps zone** that grows and shrinks as apps launch and quit.
- **Live running indicators**, drag-and-drop reordering, drop-from-Finder, and context menus.
- **Spatial targeting UI** — a visual monitor/desktop picker to move a Dock to any display or Space ([docs/09](docs/09-dock-targeting-ui.md)).
- **`dockman://` URL scheme** — script your Docks: `dockman://toggle?dock=NAME`, plus `pin`, `show`, and `hide`.
- **Resilient** — a Dock whose desktop is deleted parks on the current desktop with one-click re-pin; bindings survive login Space-ID churn; config migrates forward automatically.
- **Faceless menu-bar agent** — no icon in the system Dock; everything is managed from the menu-bar item (▤ rectangle-stack icon).

## How it works (the crux)

macOS exposes no public API to pin a window to a *specific* Space — only `.canJoinAllSpaces` (every Space) or default (current Space). The private `SkyLight.framework` does expose per-Space placement. Since macOS 14.5, Apple gates these calls with a `connection_holds_rights_on_window` check, which is why tools like *yabai* now need SIP disabled. **That check protects the *target window*, not the function.** An app's connection always holds rights on the windows it created itself. Dockman only ever moves **its own Dock windows**, so it stays inside the permitted envelope and needs **no SIP changes and no special entitlements**. Full details: [`docs/02-technical-design.md`](docs/02-technical-design.md).

> **Note:** Dockman uses private (undocumented) macOS APIs via runtime symbol lookup, with capability detection and graceful fallback. A new macOS release could change these APIs; the contract tests in this repo are the early-warning system ([docs/05](docs/05-risks-and-mitigations.md)).

---

## Installation

There are no prebuilt releases yet — you build from source, which takes about a minute.

### Requirements

- A Mac running **macOS 14 (Sonoma) or later** (developed and verified on macOS 26.5 / Apple Silicon).
- **Xcode** (with its command-line tools selected) — provides the Swift 6 toolchain.
  ```bash
  xcode-select -p   # should print /Applications/Xcode.app/Contents/Developer
  # if not: sudo xcode-select -s /Applications/Xcode.app
  ```

### Build & install

```bash
# 1. Clone the repo
git clone https://github.com/OSPK/Dockman.git
cd Dockman

# 2. Build a release binary and wrap it into an app bundle
./scripts/make-app.sh            # produces build/Dockman.app

# 3. (Optional) install it where apps live
cp -R build/Dockman.app /Applications/

# 4. Launch it
open /Applications/Dockman.app   # or: open build/Dockman.app
```

A new Dock appears on your current desktop, and a **rectangle-stack icon** appears in the menu bar — that's Dockman's control center. The app is ad-hoc signed by the build script, which is fine for an app built on your own machine; Gatekeeper will not complain.

### First launch

- On first launch, macOS may ask for **Accessibility** permission. This is **optional** — it's only needed for the "summon an app's window onto this Dock's screen when clicked" feature. Everything else works without it.
- To start Dockman automatically at login: **System Settings ▸ General ▸ Login Items ▸ +** and add `Dockman.app`.

### Using it

- **Menu bar ▸ rectangle-stack icon** — create/remove Docks, pin a Dock to a desktop, open the monitor/desktop picker, quit.
- **Drag and drop** — drag apps or files from Finder onto a Dock; drag items to reorder; right-click for context menus.
- **Scripting** — e.g. `open "dockman://toggle?dock=Work"` from a terminal, Shortcuts, or a hotkey tool.
- Configuration is stored as plain JSON at `~/Library/Application Support/xyz.waqas.dockman/config.json` (written atomically, with backup).

### Uninstall

```bash
killall dockman 2>/dev/null
rm -rf /Applications/Dockman.app
rm -rf ~/Library/Application\ Support/xyz.waqas.dockman
```

---

## Development

Dockman is a plain Swift package — no Xcode project needed.

```bash
swift build                        # build everything (debug)
swift test                         # unit + contract tests (31)
swift run dockman-spike -- --once  # feasibility gate: proves Space-pinning works on this machine, exits 0 on pass
./scripts/make-app.sh app debug    # debug build of the agent app
```

The contract tests and the spike talk to the real WindowServer, so they must run in a **GUI login session** — not over headless SSH. See [`docs/08-building.md`](docs/08-building.md) for the full build / test / sign / notarize / distribute pipeline.

### Project layout

| Module | Purpose |
|--------|---------|
| `SpacesKit` | SkyLight symbol resolution, Space topology, SIP-safe window→Space pinning, notification-driven `SpaceMonitor` |
| `ConfigKit` | Codable config model + atomic, backup-protected JSON store |
| `DockKit` | Non-activating dock window, item cells & rendering, binding resolver, per-dock controller, targeting UI |
| `Dockman` | The faceless menu-bar agent app |
| `DockmanSpike` | Phase-0 feasibility spike (round-trip pinning proof, usable as a CI gate) |

### Documentation index

| Doc | Purpose |
|-----|---------|
| [`docs/00-glossary.md`](docs/00-glossary.md) | Shared vocabulary (Space, display, DHSS, SLS, etc.) |
| [`docs/01-product-spec.md`](docs/01-product-spec.md) | Vision, personas, feature requirements, scope |
| [`docs/02-technical-design.md`](docs/02-technical-design.md) | **The core**: Spaces model, SkyLight APIs, the pinning mechanism |
| [`docs/03-architecture.md`](docs/03-architecture.md) | Modules, data model, control flow, threading, persistence |
| [`docs/04-ux-design.md`](docs/04-ux-design.md) | Visual design, interactions, settings UI, accessibility |
| [`docs/05-risks-and-mitigations.md`](docs/05-risks-and-mitigations.md) | Anticipated problems and concrete solutions |
| [`docs/06-build-distribution.md`](docs/06-build-distribution.md) | Signing, notarization, packaging, auto-update |
| [`docs/07-roadmap.md`](docs/07-roadmap.md) | Phased delivery plan with acceptance gates |
| [`docs/08-building.md`](docs/08-building.md) | Build / test / sign / notarize / deploy |
| [`docs/09-dock-targeting-ui.md`](docs/09-dock-targeting-ui.md) | The spatial monitor/desktop picker |

## Status & roadmap

| Phase | Scope | Status |
|-------|-------|--------|
| 0 — Feasibility gate | Prove SIP-safe per-Space pinning of own windows | ✅ Passed |
| 1 — Walking skeleton | Agent app, default dock, pin-to-desktop, app launching | ✅ Done |
| 2 — Resilience | Orphan parking & re-pin, binding restore across logins, fullscreen policy, config migration, multi-display reconcile | ✅ Done |
| 3 — Multiple docks & richer items | Item kinds, running-apps zone, drag-and-drop, folder stacks, URL scheme | ✅ Done |
| 4 — Design & polish | Settings window, styles, magnification, auto-hide | 🚧 Next |

**31 tests green.** Acceptance criteria verified live on a 3-display setup with "Displays have separate Spaces" off. See [`docs/07-roadmap.md`](docs/07-roadmap.md) for the full plan.

## Contributing

Issues and pull requests are welcome. Before opening a PR:

1. Read [`docs/03-architecture.md`](docs/03-architecture.md) — the module boundaries are deliberate.
2. Run `swift test` and `swift run dockman-spike -- --once` in a GUI session; both must pass.
3. Anything touching `SpacesKit` must keep the `dlsym`-based symbol indirection and capability fallbacks intact.

## License

Dockman is released under the [MIT License](LICENSE).
