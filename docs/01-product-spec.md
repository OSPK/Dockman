# 01 — Product Specification

## 1. Vision

Give power users a Dock that is **per-desktop**, not global. A user who keeps "Communication" on Desktop 1, "Design" on Desktop 2, and "Dev" on Desktop 3 should see a different, purpose-built Dock the instant they switch desktops — with the apps, folders, and shortcuts relevant to that context, and nothing else. This must work on multi-monitor setups regardless of the "Displays have separate Spaces" setting.

The system Dock is intentionally *not* replaced or hidden by default — Dockman is additive. Hiding the system Dock is an opt-in convenience the app can perform on the user's behalf.

## 2. Goals & non-goals

### Goals (v1)
- G1 — Create one or more independent Docks.
- G2 — **Pin each Dock to a specific Space** (desktop), so it only appears when that Space is active.
- G3 — Work with **DHSS OFF** (one Space spanning all displays) *and* DHSS ON.
- G4 — Pin a Dock to a specific **display** as well as a Space.
- G5 — No SIP changes, no admin rights, no kernel extension, no injection into other processes.
- G6 — Launch apps, reveal files/folders, switch to running apps; show running indicators.
- G7 — Survive display hot-plug, resolution change, Space add/remove, sleep/wake, logout/login.
- G8 — Idle CPU ≈ 0%; memory footprint small (target < 150 MB resident with a few Docks).
- G9 — Distributable as a notarized, Gatekeeper-passing, Developer-ID-signed `.app` (not Mac App Store in v1; see §8).

### Non-goals (v1)
- N1 — Replacing the system Dock's reserved screen area is **not** guaranteed (overlay/auto-hide instead; reservation is experimental — see risks).
- N2 — Managing/moving *other apps'* windows (that needs SIP-disabled territory; explicitly out of scope to stay safe).
- N3 — Live window thumbnails/previews of other apps (needs Screen Recording permission; deferred to v2).
- N4 — Per-app notification badges for arbitrary third-party apps (no public API; partial best-effort only).
- N5 — Windows/Linux. macOS only.
- N6 — iPad/Stage Manager-style window tiling.

## 3. Personas

- **The context-switcher (primary).** Organizes work into desktops; wants each desktop's Dock to reflect that context. Multi-monitor.
- **The minimalist.** Hides the system Dock entirely, wants a single clean auto-hiding Dockman bar with only 6 apps.
- **The power user / tinkerer.** Wants many Docks, keyboard triggers, scripting, fine visual control, and is comfortable granting Accessibility permission for advanced features.

## 4. Feature requirements

### 4.1 Dock management (MUST)
- Create, rename, duplicate, delete a Dock.
- Each Dock has: a **layout** (ordered list of items), a **binding** (target Space(s) + display(s)), an **appearance** (style/size/position), and **behavior** (auto-hide, magnification, etc.).
- A Dock may be bound to: *one Space*, *several Spaces*, *all Spaces* (`canJoinAllSpaces`), or the *current Space only* (follows the user — degenerate "extra dock" mode).

### 4.2 Dock items (MUST)
Item kinds:
- **App** — launches/activates an application (by bundle URL). Shows running indicator.
- **File/Folder** — opens in default app / reveals in Finder.
- **Folder stack** — fan/grid/list popover of a folder's contents (like the system Dock's stacks).
- **Separator / spacer**.
- **Action** — runs a shortcut: a deep-link URL, an AppleScript/Shortcuts action, or a Dockman command (e.g., "switch to Space N", "toggle Dock X").
- **Running-apps zone** (optional, MAY) — a dynamic region listing currently running apps not already pinned.

### 4.3 Pinning & Spaces (MUST — the core)
- UI to assign a Dock to the **current** Space with one click ("Pin here").
- UI to assign to a named/numbered Space chosen from a live list.
- Automatic re-pin on Space creation/removal and on login (bindings persisted by stable keys; see §6 of technical design).
- Correct behavior when the active Space is a **fullscreen-app Space**: Dockman Docks hide there by default (configurable per Dock).

### 4.4 Appearance (SHOULD)
- Orientation: bottom, top, left, right, or free-floating island.
- Styles: *Classic* (translucent), *Liquid Glass* (macOS 26 `NSGlassEffectView`), *Solid*, *Minimal*.
- Icon size + magnification on hover (Dock-like genie optional).
- Per-Dock accent/tint; light/dark adaptive.

### 4.5 Behavior (SHOULD)
- Auto-hide with edge reveal + configurable reveal delay.
- "Always on top" vs "behind active window" levels.
- Hide when a fullscreen app is frontmost.
- Optional: hide the **system** Dock while Dockman is active (via the documented `com.apple.dock autohide` preference, restored on quit).

### 4.6 Triggers & control (MAY)
- Global hotkey to toggle a Dock or peek all Docks.
- Menu-bar status item: list Docks, quick-toggle, open settings, quit.
- URL scheme `dockman://` for scripting (`dockman://toggle?dock=Dev`).

### 4.7 Persistence & sync (MUST persist; sync is MAY)
- All Docks/bindings/appearance persisted locally (JSON in Application Support).
- Export/import a configuration bundle.
- iCloud/Drive sync is out of scope for v1.

## 5. Functional acceptance criteria (sample, testable)

| ID | Given | When | Then |
|----|-------|------|------|
| AC-1 | DHSS OFF, 2 displays, Dock "Dev" pinned to Space 3 | user switches to Space 3 | "Dev" appears on its assigned display within ≤ 150 ms, on no other Space |
| AC-2 | Dock "Dev" pinned to Space 3 | user switches to Space 1 | "Dev" is not visible anywhere |
| AC-3 | Dock pinned to Space 3 | user enters a fullscreen app (new Space) | no Dockman Dock is shown (unless that Dock opted into fullscreen) |
| AC-4 | A Dock pinned to Space 3 | user deletes Space 3 in Mission Control | Dockman re-binds gracefully (orphan handling: park on nearest/created Space, notify) without crash |
| AC-5 | Any Dock visible | user clicks an app icon | target app launches/activates **without** stealing key focus transition artifacts; Dockman never becomes the active app |
| AC-6 | App running for 30 min, idle | — | Dockman CPU averages < 0.5% and uses notification-driven updates (no busy poll) |
| AC-7 | Display unplugged then replugged | — | Docks bound to that display reappear correctly; no duplicate/ghost windows |
| AC-8 | Logout then login | — | All Docks restore to their bound Spaces/displays by stable keys |

## 6. Constraints

- **No SIP disable, no process injection, no private entitlements.** Hard constraint (defines the safe envelope).
- Private SkyLight symbols used **only** against Dockman's own windows.
- Must degrade gracefully if a private symbol disappears in a future macOS (fallback to public `.canJoinAllSpaces` + manual show/hide; see risks R-1).
- Must run sandbox-friendly *enough* to notarize (hardened runtime). Full App Sandbox is **not** required for v1 distribution and likely incompatible with SkyLight; revisit for MAS.

## 7. Success metrics

- Functional: AC-1…AC-8 pass on macOS 14/15/26, single + dual display, DHSS on/off.
- Performance: idle CPU < 0.5%, space-switch latency < 150 ms, memory < 150 MB.
- Stability: zero crashes across a 72-hour soak with periodic Space switching and display hot-plug.

## 8. Distribution stance

v1 ships **outside** the Mac App Store as a Developer-ID-signed, notarized app, because (a) private-API use and (b) lack of full App Sandbox make MAS review unlikely. A future "MAS-lite" build could drop hard-pinning and fall back to `canJoinAllSpaces`-only mode. See [`06-build-distribution.md`](06-build-distribution.md).
