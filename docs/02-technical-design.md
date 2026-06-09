# 02 — Technical Design (Core)

This is the load-bearing document. It explains the macOS Spaces model, the exact private interface used, the SIP-safety argument, the window configuration, and every edge case in the pin mechanism.

> All code is illustrative Swift/C. Symbol signatures are reconstructed from the SkyLight ABI as used by open tools (yabai, Übersicht, SkyLightWindow). Treat them as a starting contract to be verified against the running system in Phase 0 (see roadmap).

---

## 1. The macOS Spaces model

### 1.1 What a "Space" is
A Space is a virtual desktop owned by the **WindowServer**. Each has a stable 64-bit **Managed Space ID** and a string UUID. Spaces come in types:

| Type value | Meaning |
|-----------:|---------|
| `0` | User/standard desktop Space |
| `2` | Fullscreen-app Space (auto-created when an app enters native fullscreen; destroyed on exit) |
| `4` | System (legacy, e.g. old Dashboard) |

### 1.2 "Displays have separate Spaces" (DHSS) — the two topologies

Dockman must handle **both** topologies because the user explicitly wants pinning to work with DHSS **off**.

**DHSS ON (default).** Each physical display has its own independent stack of Spaces and its own menu bar. `SLSCopyManagedDisplaySpaces` returns **one managed-display entry per physical display**, each with its own `Spaces` array and `Current Space`.

```
[
  { "Display Identifier": "<uuid-of-display-1>", "Current Space": {id64:7,...},
    "Spaces": [ {id64:7,type:0}, {id64:9,type:0} ] },
  { "Display Identifier": "<uuid-of-display-2>", "Current Space": {id64:8,...},
    "Spaces": [ {id64:8,type:0}, {id64:12,type:0} ] }
]
```

**DHSS OFF.** Spaces span **all** displays simultaneously. `SLSCopyManagedDisplaySpaces` returns a **single** managed-display entry (its `Display Identifier` is the string `"Main"`) whose `Spaces` array is the global desktop stack. Secondary displays render the same Space; only the main display has a menu bar.

```
[
  { "Display Identifier": "Main", "Current Space": {id64:3,...},
    "Spaces": [ {id64:3,type:0}, {id64:5,type:0}, {id64:6,type:0} ] }
]
```

**Design consequence.** A Dock's binding is `(spaceID, displayUUID)`. With DHSS OFF, the *same* `spaceID` is valid on every display, so to show a Dock on Space 3 on both monitors we create **two windows** (one per display frame), both assigned to Space 3. With DHSS ON, a `spaceID` only exists within one display's stack, so the binding's display is implied by the Space.

We detect the topology at startup and on display reconfiguration by:
1. Reading the `com.apple.spaces` `spans-displays` preference (1 ⇒ DHSS off), **and**
2. Inspecting whether `SLSCopyManagedDisplaySpaces` returns a single `"Main"` entry vs one per display.

(2) is authoritative; (1) is a fast hint.

---

## 2. The private interface (SkyLight)

### 2.1 Why private API is unavoidable
Public AppKit offers only:
- `NSWindow.collectionBehavior = .canJoinAllSpaces` → window on **every** Space.
- default → window on the **current** Space at creation time.

There is **no public way to say "this window belongs to Space #3 and no other."** That capability lives only in SkyLight. Hence Dockman uses it — but narrowly and safely (§3).

### 2.2 The SIP-safety argument (most important section)

The WindowServer authorizes window mutations with an internal check, `connection_holds_rights_on_window(connection, windowID)`. Tightened in **macOS 14.5**, it is why *yabai* and similar now require SIP disabled.

**Critical nuance:** the check protects the **target window**, not the function. A process's connection **always holds rights on windows that process created**. `Dock.app` additionally has a special "universal owner" connection letting it touch any window.

> **Therefore: Dockman moves only its *own* Dock windows between Spaces. Those windows are created by Dockman's own connection, so `connection_holds_rights_on_window` passes. No SIP change, no injection, no special entitlement is required.**

This is the entire reason the product is feasible. Every use of SkyLight in Dockman MUST be against a `windowNumber` belonging to a Dockman `NSWindow`. A code-level invariant and an assertion guard enforce this (§3.4).

### 2.3 Symbols used (the complete list)

Loaded from `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`. We bind them at runtime with `dlopen`/`dlsym` (not link-time) so a missing symbol on a future OS is a recoverable runtime condition, not a launch failure (see §6 and risks R-1).

```c
// Connection
typedef int CGSConnectionID;
CGSConnectionID SLSMainConnectionID(void);

// Enumerate displays/spaces  ->  CFArrayRef of CFDictionaryRef (see §1.2)
CFArrayRef SLSCopyManagedDisplaySpaces(CGSConnectionID cid);

// Current space for a display (displayUUID as CFStringRef)
uint64_t SLSManagedDisplayGetCurrentSpace(CGSConnectionID cid, CFStringRef displayUUID);

// Assign / unassign windows to spaces.
//   windows: CFArrayRef of CFNumberRef (CGWindowID)
//   spaces:  CFArrayRef of CFNumberRef (uint64 space id)
void SLSAddWindowsToSpaces(CGSConnectionID cid, CFArrayRef windows, CFArrayRef spaces);
void SLSRemoveWindowsFromSpaces(CGSConnectionID cid, CFArrayRef windows, CFArrayRef spaces);

// Move windows so they belong to EXACTLY one space (clears others).
void SLSMoveWindowsToManagedSpace(CGSConnectionID cid, CFArrayRef windows, uint64_t spaceID);

// Which spaces does a window currently belong to?  (mask: 0x7 typical)
CFArrayRef SLSCopySpacesForWindows(CGSConnectionID cid, int mask, CFArrayRef windows);

// Space type (0 user / 2 fullscreen / 4 system)
int SLSSpaceGetType(CGSConnectionID cid, uint64_t spaceID);

// Optional: low-level space-change notifications
typedef void (*SLSNotifyProc)(uint32_t event, void *data, size_t dataLen, void *ctx);
CGError SLSRegisterNotifyProc(SLSNotifyProc proc, uint32_t event, void *ctx);
```

> Legacy `CGS*` aliases (`CGSMainConnectionID`, `CGSAddWindowsToSpaces`, …) are re-exported by CoreGraphics and remain present, but we standardize on `SLS*` from SkyLight, with `CGS*` as a fallback name to try in `dlsym` if `SLS*` is absent.

### 2.4 What is **read-only / unprotected** vs **mutating**
- **Read-only (always safe, never needs window rights):** `SLSCopyManagedDisplaySpaces`, `SLSManagedDisplayGetCurrentSpace`, `SLSSpaceGetType`, `SLSCopySpacesForWindows`. Used freely for topology and current-Space detection.
- **Mutating (needs window rights — we only call on our own windows):** `SLSAddWindowsToSpaces`, `SLSRemoveWindowsFromSpaces`, `SLSMoveWindowsToManagedSpace`.

---

## 3. The pinning mechanism

### 3.1 The Dock window
Each Dockman Dock surface is a custom `NSPanel`:

```swift
final class DockPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false

        // Sit at the system Dock's window level by default (configurable).
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))  // ~20

        // We manage Space membership ourselves via SkyLight, so DO NOT use
        // .canJoinAllSpaces here. Keep it out of Mission Control cycling and
        // stationary during Exposé.
        collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
    }
    override var canBecomeKey: Bool { false }   // never steal focus
    override var canBecomeMain: Bool { false }
}
```

Key window-config decisions and *why*:
- **`.nonactivatingPanel` + `canBecomeKey=false`** → clicking a Dock item never makes Dockman the active app; the user's frontmost app keeps focus. Essential for "extra Dock" feel (AC-5).
- **No `.canJoinAllSpaces`** in pinned mode → we want exclusive Space membership, set explicitly by SkyLight.
- **`.stationary`** → the window doesn't slide away during Mission Control/Exposé.
- **`.ignoresCycle`** → excluded from Cmd-Tab/window cycling.
- **`.fullScreenAuxiliary`** → *allowed* to appear over fullscreen windows if a Dock opts in; default behavior still hides on fullscreen Spaces because we simply don't assign the window to those Spaces.
- **Window level** = `kCGDockWindowLevel` by default; configurable to `.floating`, `.statusBar`, or "behind active window" via a lower level.

### 3.2 Assigning a window to a Space
```swift
func pin(window: NSWindow, toSpace spaceID: UInt64) {
    let cid = SLSMainConnectionID()
    let wid = CGWindowID(window.windowNumber)
    assert(ownsWindow(wid))                       // SIP-safety invariant (§3.4)
    let windows = [wid] as CFArray                // array of CFNumber
    SLSMoveWindowsToManagedSpace(cid, windows, spaceID)
}
```
`SLSMoveWindowsToManagedSpace` makes the window belong to **exactly** `spaceID`. When the user switches to that Space, the WindowServer shows the window; on every other Space it is absent. **No per-switch show/hide code, no flicker** — the compositor does it.

For multi-Space bindings (a Dock that should appear on Spaces {3,5,7}) use add/remove instead:
```swift
func pin(window: NSWindow, toSpaces ids: [UInt64]) {
    let cid = SLSMainConnectionID(); let wid = CGWindowID(window.windowNumber)
    let current = currentSpaces(of: wid)                       // SLSCopySpacesForWindows
    let toAdd = Set(ids).subtracting(current)
    let toRemove = current.subtracting(ids)
    if !toRemove.isEmpty { SLSRemoveWindowsFromSpaces(cid, [wid] as CFArray, Array(toRemove) as CFArray) }
    if !toAdd.isEmpty    { SLSAddWindowsToSpaces(cid,    [wid] as CFArray, Array(toAdd)    as CFArray) }
}
```

### 3.3 Multi-display under DHSS OFF
For a Dock bound to `(space: 3, displays: [A,B])` with DHSS OFF:
1. Create window `W_A` framed on display A and `W_B` framed on display B.
2. `SLSMoveWindowsToManagedSpace(cid, [W_A,W_B], 3)`.
Both windows live on the single global Space 3 but are positioned on different monitors. The `Dock` model owns an array of `(displayUUID → NSWindow)`; the renderer keeps them in sync.

### 3.4 SIP-safety invariant (enforced)
```swift
private let ownedWindowNumbers = NSHashTable<NSWindow>.weakObjects()
func ownsWindow(_ wid: CGWindowID) -> Bool {
    ownedWindowNumbers.allObjects.contains { CGWindowID($0.windowNumber) == wid }
}
```
Every mutating SkyLight call is funneled through one `SpacesService` method that `assert`s `ownsWindow`. In release builds the guard early-returns instead of crashing. This makes "only touch our own windows" a structural property, not a convention.

---

## 4. Detecting Space changes

Two layers, for robustness:

1. **Primary — AppKit notification.** `NSWorkspace.shared.notificationCenter` ▸ `NSWorkspace.activeSpaceDidChangeNotification`. Fires on every Space switch. It does **not** say *which* Space, so on receipt we re-query `SLSManagedDisplayGetCurrentSpace` per display.

2. **Secondary — SkyLight notify proc (optional).** `SLSRegisterNotifyProc` for the space-changed event gives lower latency and richer data, but the event numbers are undocumented and version-sensitive. Treated as an optional fast-path; the AppKit notification is the source of truth.

We **never** busy-poll. A debounced re-query (≤ 50 ms coalescing) runs only in response to: active-space change, display reconfigure (`NSApplication.didChangeScreenParametersNotification`), wake (`NSWorkspace.didWakeNotification`), and Space add/remove (detected by diffing `SLSCopyManagedDisplaySpaces` snapshots taken on the above events).

### 4.1 Reaction to a Space switch (what actually happens on screen)
Because windows are pre-assigned to their Spaces via SkyLight, the *visual* switch is handled entirely by the WindowServer — Dockman does nothing on the hot path. Dockman's notification handler only does bookkeeping: update "current Space" state for the status-item UI, hide/show logic for *fullscreen* Spaces (where no window is assigned), and lazily create windows for newly discovered Spaces that have bindings.

---

## 5. Persistence of bindings across sessions

Managed Space IDs are stable within a login session but **not guaranteed across reboots**. Dockman therefore stores a **composite key** per Space and re-resolves on login:

```json
{
  "binding": {
    "primaryKey": { "spaceID": 3, "spaceUUID": "F1C2-..." },
    "ordinalFallback": { "displayUUID": "A1B2-...", "spaceIndex": 2 },
    "displays": ["A1B2-..."]
  }
}
```

Resolution order on login / Space-set change:
1. Match by `spaceUUID` (most stable).
2. Else match by `spaceID`.
3. Else **ordinal fallback**: the Nth Space (0-based `spaceIndex`) within the display's stack. Handles the common "IDs changed but the desktop layout is the same" case.
4. Else mark binding **orphaned**: park the Dock on the current Space and surface a non-blocking notification offering re-pin. (AC-4)

The resolver re-runs whenever `SLSCopyManagedDisplaySpaces` diffs (Space added/removed/reordered).

---

## 6. Private-API abstraction & graceful degradation

All SkyLight access sits behind one protocol so the rest of the app is private-API-free:

```swift
protocol SpacesService {
    var capabilities: SpacesCapabilities { get }     // which features resolved at runtime
    func managedDisplaySpaces() -> [ManagedDisplay]
    func currentSpace(displayUUID: String) -> UInt64?
    func spaceType(_ id: UInt64) -> SpaceType
    func spaces(of window: CGWindowID) -> Set<UInt64>
    func move(window: CGWindowID, toExactly spaceID: UInt64)         // mutating, own-window only
    func set(window: CGWindowID, spaces: Set<UInt64>)               // mutating, own-window only
}
```

Concrete `SkyLightSpacesService` resolves every symbol via `dlsym` at init, trying `SLS*` then `CGS*` names, and records which succeeded in `capabilities`. If the core mutating symbols are unavailable (hypothetical future OS), the app:
- Disables hard-pinning,
- Falls back to **`.canJoinAllSpaces` + manual hide/show** on `activeSpaceDidChange` (the public-only mode), and
- Shows a one-time banner explaining reduced fidelity (slight flicker on switch).

This keeps Dockman shippable even if Apple changes SkyLight, and is the basis of a possible Mac App Store "lite" build.

---

## 7. Screen-area reservation (the genuinely hard feature)

The system Dock shrinks `NSScreen.visibleFrame` so maximized/zoomed windows don't overlap it. **Third-party apps cannot do this with public API.** Options, in order of preference:

1. **Overlay (default).** Float above windows; windows may pass underneath. Zero risk. Most third-party docks do this.
2. **Auto-hide.** Dock is off-screen until the cursor reaches the screen edge (tracked with a thin always-on edge `NSTrackingArea` / a `CGEventTap` for the mouse-moved location). Sidesteps reservation entirely; pairs perfectly with overlay.
3. **Experimental reservation.** Undocumented WindowServer "reserved area" calls exist but are fragile and partly behind the same rights checks. Marked experimental, off by default, behind a clearly-labeled toggle. See risks R-7.

v1 ships **overlay + auto-hide**. Reservation is a research spike, not a commitment.

---

## 8. Fullscreen handling (detail)

Native fullscreen creates a new Space of `type == 2`. Dockman simply **never assigns** Dock windows to type-2 Spaces, so Docks naturally vanish in fullscreen. A per-Dock "show over fullscreen" option, when enabled, sets `.fullScreenAuxiliary` and assigns the window to the fullscreen Space's ID as it appears (re-evaluated on each Space-set diff). Default OFF.

---

## 9. App/launcher mechanics (no private API)

- Running apps & icons: `NSWorkspace.shared.runningApplications`, `NSRunningApplication.icon`.
- Pinned-app icons: `NSWorkspace.shared.icon(forFile: appURL.path)` (cache by bundle id + mtime).
- Launch / activate: `NSWorkspace.shared.openApplication(at:configuration:)`; `runningApp.activate()`.
- Reveal files: `NSWorkspace.shared.activateFileViewerSelecting([url])`.
- Folder stacks: enumerate with `FileManager`, render a popover.
- Running indicator: derive from `runningApplications` membership + `isActive`; refresh on `NSWorkspace.didLaunch/didTerminateApplicationNotification`.
- **Limitations (documented to user):** per-app unread badges for arbitrary apps have no public API; live window previews need Screen Recording (deferred). These are honest v1 gaps, not bugs.

---

## 10. End-to-end sequence (pin "Dev" to current Space, DHSS OFF, dual monitor)

```
User: clicks "Pin Dock 'Dev' here"
 └─ Controller asks SpacesService.currentSpace(mainDisplayUUID) -> 3
 └─ Controller asks SpacesService.managedDisplaySpaces() -> single "Main" entry, displays {A,B}
 └─ DockRenderer ensures windows W_A (on A), W_B (on B) exist for "Dev"
 └─ SpacesService.move(window: W_A, toExactly: 3)
 └─ SpacesService.move(window: W_B, toExactly: 3)
 └─ Binding persisted: {spaceUUID:"F1C2", spaceID:3, displays:[A,B], ordinal:2}
Result: "Dev" visible on both monitors only while Space 3 is active.
User switches to Space 1: WindowServer hides W_A/W_B automatically. Dockman does nothing.
```

This is the whole product in ten lines. Everything else is UI, persistence, resilience, and polish.
