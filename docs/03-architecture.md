# 03 — Software Architecture

## 1. Tech stack

| Concern | Choice | Rationale |
|--------|--------|-----------|
| Language | **Swift 6** (strict concurrency) | Native, first-class AppKit/SkyLight interop |
| UI — Dock surface | **AppKit + Core Animation** (`CALayer`) | Maximum control over window level, non-activation, magnification, perf |
| UI — Settings | **SwiftUI** hosted in an `NSWindow` | Fast to build forms/lists; not on the perf-critical path |
| Private interop | **C shim + `dlopen`/`dlsym`** | Runtime symbol binding ⇒ graceful degradation |
| Persistence | **Codable JSON** in `Application Support` | Human-readable, diff-able, exportable |
| Login item | **`ServiceManagement` `SMAppService`** | Modern, sandbox-friendly auto-start |
| Global hotkeys | **`CGEventTap`** (or Carbon `RegisterEventHotKey`) | System-wide triggers |
| Packaging | Developer-ID `.app`, notarized DMG, **Sparkle** updater | Outside MAS (see build doc) |
| Min OS | macOS 14.0; primary target macOS 26 | Covers Sonoma→Tahoe |

Project layout: a thin `Dockman.app` executable + Swift packages (`SpacesKit`, `DockKit`, `ConfigKit`, `UIKitAppKit`) for testability.

## 2. Module map

```
Dockman.app
├── AppDelegate / DockmanApp        (lifecycle, agent setup, status item)
│
├── SpacesKit                       ── all WindowServer interaction ──
│   ├── SkyLightShim (C)            dlopen/dlsym of SLS* symbols
│   ├── SpacesService (protocol)    public surface; SIP-safe API
│   ├── SkyLightSpacesService       concrete impl + capability detection
│   ├── FallbackSpacesService       public-only (.canJoinAllSpaces) mode
│   ├── SpaceTopology               DHSS detection, display↔space mapping
│   └── SpaceMonitor                notifications, debounce, snapshot diffing
│
├── DockKit                         ── a Dock and its windows ──
│   ├── DockModel                   items, binding, appearance, behavior
│   ├── DockController              owns N DockPanels (one per display)
│   ├── DockPanel (NSPanel)         non-activating, borderless surface
│   ├── DockLayerRenderer (CALayer) icons, magnification, indicators
│   ├── ItemProviders               App/File/Stack/Action/RunningZone
│   └── AutoHideEngine              edge tracking, reveal animation
│
├── BindingKit
│   ├── BindingResolver             composite-key resolution (uuid→id→ordinal)
│   └── OrphanHandler               parks/notifies on Space deletion
│
├── ConfigKit
│   ├── Config (Codable)            top-level document
│   ├── ConfigStore                 atomic load/save, migration, export/import
│   └── IconCache
│
├── ControlKit
│   ├── StatusItemController        menu-bar UI
│   ├── HotkeyService               CGEventTap global hotkeys
│   └── URLSchemeHandler            dockman:// commands
│
└── UI (SwiftUI)
    ├── SettingsWindow              Docks list, editor, appearance, behavior
    ├── PinSheet                    live Space/display picker
    └── PermissionsCoach           Accessibility/SR prompts (only if used)
```

**Dependency rule:** everything depends *inward* on `SpacesKit`/`ConfigKit`; nothing outside `SpacesKit/SkyLightShim` imports a private symbol. This keeps the blast radius of any macOS change to one module.

## 3. Data model (Codable)

```swift
struct Config: Codable {                 // the persisted document (v-tagged)
    var schemaVersion: Int               // for migrations
    var docks: [DockModel]
    var globalSettings: GlobalSettings   // hide-system-dock, default style, hotkeys
}

struct DockModel: Codable, Identifiable {
    let id: UUID
    var name: String
    var items: [DockItem]
    var binding: Binding                 // where it appears
    var appearance: Appearance           // style, size, orientation, tint, magnify
    var behavior: Behavior               // autoHide, level, showOnFullscreen, ...
    var enabled: Bool
}

enum DockItem: Codable {                 // sum type, tagged-union JSON
    case app(bundleURL: URL, label: String?)
    case file(url: URL)
    case folderStack(url: URL, style: StackStyle)
    case action(Action)
    case separator
    case spacer(points: CGFloat)
    case runningAppsZone(filter: RunningFilter)
}

struct Binding: Codable {
    enum Mode: Codable { case spaces([SpaceRef]); case allSpaces; case currentSpace }
    var mode: Mode
    var displays: [String]               // display UUIDs; empty = all displays
}

struct SpaceRef: Codable {               // composite key (see technical design §5)
    var spaceUUID: String?
    var spaceID: UInt64?
    var displayUUID: String?
    var ordinalIndex: Int?
}
```

`SpaceRef` deliberately stores three resolution keys so a Space can be re-found after IDs churn.

## 4. Runtime control flow

### 4.1 Launch
```
DockmanApp.didFinishLaunching
 ├─ become LSUIElement agent (no system Dock icon)
 ├─ ConfigStore.load() → Config
 ├─ SpacesKit.bootstrap()
 │    ├─ SkyLightSpacesService.resolveSymbols()  → capabilities
 │    │     (if core mutators missing → swap in FallbackSpacesService + banner)
 │    └─ SpaceTopology.detect()  (DHSS on/off, displays, space stacks)
 ├─ for each enabled DockModel:
 │    ├─ BindingResolver.resolve(binding, topology) → concrete (spaceIDs, displays)
 │    ├─ DockController.create(windows per display)
 │    └─ SpacesService.set(window, spaces)          // pin via SkyLight
 ├─ SpaceMonitor.start()  (register notifications)
 ├─ StatusItemController.install()
 ├─ HotkeyService.register(globalSettings.hotkeys)
 └─ URLSchemeHandler.register()
```

### 4.2 Space switch (hot path is empty by design)
```
NSWorkspace.activeSpaceDidChange
 └─ SpaceMonitor (debounced 50ms)
     ├─ currentSpaceID per display (read-only SLS)
     ├─ update StatusItem "current desktop" label
     ├─ if current space.type == fullscreen → ensure no overlay shown
     └─ if a binding references a space we haven't materialized a window for yet
          → lazily create & pin it
   (No work needed to SHOW/HIDE bound docks — WindowServer already did it.)
```

### 4.3 Space set changed (add/remove/reorder)
```
SpaceMonitor detects SLSCopyManagedDisplaySpaces diff
 ├─ BindingResolver re-resolves every binding (uuid→id→ordinal)
 ├─ OrphanHandler handles bindings whose Space vanished
 └─ DockController reconciles windows (create/destroy/repin) to match
```

### 4.4 Display reconfigure / hot-plug
```
NSApplication.didChangeScreenParameters  &  CGDisplayReconfigurationCallback
 ├─ SpaceTopology.redetect()  (DHSS topology can effectively change)
 ├─ DockController: drop windows for gone displays, add for new displays
 └─ reposition all dock frames; re-pin
```

### 4.5 Sleep/wake & login
```
NSWorkspace.didWake → full reconcile (treat like display reconfigure)
Login              → §4.1 launch path; bindings restored by composite key
```

## 5. Concurrency model

- **Main actor owns everything WindowServer-related.** All `SLS*` calls, all `NSWindow` mutation, all `CALayer` work happen on `@MainActor`. WindowServer IPC is not thread-safe across connections; serializing on main avoids races.
- Off-main work is limited to: icon decoding, folder enumeration, config (de)serialization, image caching — done on a background `actor` and hopped back to main for UI.
- Swift 6 strict concurrency enforced; `SpacesService` is `@MainActor`.
- Debouncing via a main-actor `Task` with cancellation, not timers-in-flight, to avoid pile-ups on rapid Space switching.

## 6. Persistence & migration

- Single `config.json` written **atomically** (`Data.write(options:.atomic)`) under
  `~/Library/Application Support/xyz.waqas.dockman/`.
- `schemaVersion` drives a forward-only migration chain (`migrate_v1_to_v2`, …).
- Icon cache and resolved-binding cache are separate, regenerable files (safe to delete).
- Export/import = zip of `config.json` + referenced bookmark data; security-scoped bookmarks for file/folder items so paths survive sandboxing/renames.

## 7. Error handling & observability

- `SpacesService` methods return typed results; mutating calls that hit an unexpected WindowServer error log once, surface a capability downgrade, and never crash.
- Structured logging via `os.Logger` subsystems (`spaces`, `dock`, `binding`, `config`). A "Diagnostics" panel can export a redacted log + topology snapshot for bug reports.
- Feature flags (UserDefaults) to disable the SkyLight path entirely (forces FallbackSpacesService) — invaluable for triage on a new macOS build.

## 8. Testing strategy (summary; details in roadmap)

- **`SpacesService` is a protocol** ⇒ a `MockSpacesService` drives unit tests for `BindingResolver`, `OrphanHandler`, topology mapping, and `DockController` reconciliation without a real WindowServer.
- A `SpacesContractTests` target runs against the **real** SkyLight on CI-attached hardware (not headless) to detect symbol/ABI drift early.
- UI snapshot tests for the renderer; integration "soak" harness that scripts Space switches via `SLS* ` + Mission Control AppleScript.
