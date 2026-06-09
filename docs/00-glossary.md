# 00 — Glossary

Precise definitions used throughout the spec. Where a term has a casual meaning and a technical meaning, both are given.

| Term | Definition |
|------|------------|
| **Dock (system)** | The single built-in macOS Dock managed by `Dock.app`. One per system; follows the active display. |
| **Dock (Dockman)** | An independent, app-managed Dock window created by Dockman. There can be many. Each is an `NSPanel`. |
| **Space** | A macOS virtual desktop, managed by the WindowServer. Identified internally by a 64-bit **Managed Space ID**. Created/destroyed via Mission Control. Types: *user* (standard), *fullscreen* (auto-created when an app goes native-fullscreen), *system*. |
| **Managed Space ID** | The stable 64-bit integer the WindowServer uses to identify a Space (`ManagedSpaceID` / `id64` keys in `SLSCopyManagedDisplaySpaces`). Persists across the login session; not guaranteed across reboots. |
| **Space UUID** | A string UUID also returned for each Space. More stable for persistence than the integer in some cases; used as a secondary key. |
| **Display** | A physical (or virtual) screen. Identified by a `CGDirectDisplayID` (session-scoped) and a stable **display UUID** (`CGDisplayCreateUUIDFromDisplayID`). |
| **DHSS — "Displays have separate Spaces"** | System Settings ▸ Desktop & Dock toggle. **ON** (default): every display owns its own independent stack of Spaces and its own menu bar. **OFF**: one Space spans *all* displays simultaneously; only the main display has the menu bar. Changing it requires log-out. Stored in `com.apple.spaces` pref domain (`spans-displays`). |
| **Active Space** | The Space currently displayed on a given managed display. Changes when the user switches desktops. |
| **SkyLight / SLS** | `/System/Library/PrivateFrameworks/SkyLight.framework`. The private client library that talks to the WindowServer over Mach IPC. Functions are prefixed `SLS*` (modern) or `CGS*` (legacy aliases still re-exported by CoreGraphics). |
| **WindowServer** | The system process (`WindowServer`) that owns the display, compositing, Spaces, and input routing. SkyLight is its client API. |
| **Connection** | Each process has a SkyLight *connection* (`SLSMainConnectionID()`), used by the WindowServer as an authorization token to decide which windows the process may modify. |
| **`connection_holds_rights_on_window`** | The internal WindowServer authorization check (tightened in macOS 14.5) that permits a connection to modify a window only if it owns it (or is the special "universal owner", i.e. `Dock.app`). The reason Dockman restricts itself to its own windows. |
| **CGWindowID** | A 32-bit window identifier (`window.windowNumber` in AppKit) used to refer to a window in SkyLight/CoreGraphics calls. |
| **SIP** | System Integrity Protection. Dockman is designed to require it **enabled** (the normal state). |
| **LSUIElement** | `Info.plist` flag making the app an *agent*: no system-Dock icon, no app menu in the menu bar. Dockman runs as an agent. |
| **Status item** | The menu-bar icon (`NSStatusItem`) that is Dockman's only always-visible system UI. |
| **Liquid Glass** | macOS 26 (Tahoe) design language; new `NSGlassEffectView` / SwiftUI `.glassEffect()` materials. Dockman offers a glass visual style to match. |
| **Pin / Binding** | The association `Dock ⟶ {Space, Display}` that determines on which desktop(s)/screen(s) a given Dockman Dock appears. |
| **Overlay dock** | A Dock that floats above app windows without reserving screen space (windows can pass under it). Dockman's default model. |
| **Reserved dock** | A Dock that carves out exclusive screen area so maximized windows don't overlap it (as the system Dock does). Experimental in Dockman; see risks doc. |
