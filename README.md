# Dockman

A native macOS app that creates additional, fully customizable Docks which can be **pinned to specific desktops (Spaces)** — including the case where the system setting **"Displays have separate Spaces" is disabled**.

> Target platform verified for this spec: **macOS 26.5 (Tahoe), Apple Silicon (arm64)**. Designed to also run on macOS 14 (Sonoma) and 15 (Sequoia).

---

## The one-paragraph pitch

The built-in macOS Dock is a singleton: there is exactly one, it follows the active display, and you cannot have a different Dock per virtual desktop. Dockman lets a user place one or more independent Docks and **bind each to a particular Space** so that switching desktops switches which Dock(s) you see. It does this without disabling System Integrity Protection (SIP), without a kernel/Dock injection, and without requiring "Displays have separate Spaces" to be enabled — by exploiting the fact that an app is always permitted to move **its own** windows between Spaces via the private `SkyLight` WindowServer interface.

## Why this is technically possible (the crux)

macOS exposes no public API to pin a window to a *specific* Space — only `.canJoinAllSpaces` (every Space) or default (current Space). The private `SkyLight.framework` does expose per-Space placement. Since macOS 14.5, Apple gates these calls with a `connection_holds_rights_on_window` check, which is why tools like *yabai* now need SIP disabled. **That check protects the *target window*, not the function.** An app's connection always holds rights on the windows it created itself. Dockman only ever moves **its own Dock windows**, so it stays inside the permitted envelope and needs **no SIP changes and no special entitlement**. See [`docs/02-technical-design.md`](docs/02-technical-design.md).

## Documentation index

| Doc | Purpose |
|-----|---------|
| [`docs/00-glossary.md`](docs/00-glossary.md) | Shared vocabulary (Space, display, DHSS, SLS, etc.) |
| [`docs/01-product-spec.md`](docs/01-product-spec.md) | Vision, personas, feature requirements, scope |
| [`docs/02-technical-design.md`](docs/02-technical-design.md) | **The core**: Spaces model, SkyLight APIs, the pinning mechanism, window config |
| [`docs/03-architecture.md`](docs/03-architecture.md) | Modules, data model, control flow, threading, persistence |
| [`docs/04-ux-design.md`](docs/04-ux-design.md) | Visual design, interactions, settings UI, accessibility |
| [`docs/05-risks-and-mitigations.md`](docs/05-risks-and-mitigations.md) | Anticipated problems and concrete solutions |
| [`docs/06-build-distribution.md`](docs/06-build-distribution.md) | Signing, notarization, packaging, auto-update |
| [`docs/07-roadmap.md`](docs/07-roadmap.md) | Phased delivery plan with acceptance gates |
| [`docs/08-building.md`](docs/08-building.md) | Build / test / sign / notarize / deploy on this machine |
| [`docs/09-dock-targeting-ui.md`](docs/09-dock-targeting-ui.md) | The spatial monitor/space picker — move a Dock to any display/desktop |

## Build & run

```bash
swift build                        # build everything
swift test                         # all unit + contract tests (14)
swift run dockman-spike -- --once  # Phase-0: prove space-pinning on this machine (exits 0 on pass)

./scripts/make-app.sh app && open build/Dockman.app   # the real agent app
# Manage docks from the menu-bar item ▸ (rectangle.stack icon). Quit there or `killall dockman`.
```

See [`docs/08-building.md`](docs/08-building.md) for full build / test / sign / notarize / deploy steps.

## Status

**Phase 0 (feasibility gate): ✅ PASSED** and **Phase 1 (walking skeleton): ✅ IMPLEMENTED**
on macOS 26.5.1 / Apple Silicon (with "Displays have separate Spaces" **OFF**, across 3 displays).

- `SpacesKit` — SkyLight symbol resolution, topology read, SIP-safe window→Space pinning, notification-driven `SpaceMonitor`.
- `ConfigKit` — Codable config model + atomic, backup-protected store.
- `DockKit` — non-activating dock window, icon renderer, binding resolver, per-dock controller.
- `dockman` — the faceless agent app: auto-creates a default dock, pins it to the current desktop, launches apps, all driven from a menu-bar item.

**Phase 2 (resilience): ✅ IMPLEMENTED** — orphan handling (a Dock whose desktop is deleted
parks on the current desktop with a one-click re-pin), exact-vs-ordinal binding resolution
(login id-churn restores; live deletes don't grab a neighbor), fullscreen hide policy,
forward config migration, and multi-display reconcile on display changes.

**Phase 3 (multiple docks & richer items): ✅ IMPLEMENTED** — item kinds (app, file, folder
stack, spacer, separator, action, **running-apps zone**), live running indicators, drag-and-drop
(reorder + drop-from-Finder), context menus, folder-stack popovers, and a **`dockman://` URL
scheme** (`toggle`/`pin`/`show`/`hide?dock=NAME`).

Verified live: docks pin to their bound Space and show **only** there (AC-1, AC-2); orphaned
docks park gracefully (AC-4); the running-apps zone grows/shrinks as apps launch/quit; the URL
scheme toggles a dock on/off. **31 tests green.** Next: Phase 4 (design & polish — settings
window, styles/Liquid Glass, magnification, auto-hide). See [`docs/07-roadmap.md`](docs/07-roadmap.md).
