# 04 — Design & UX

## 1. Design principles
1. **Native first.** Look like it belongs on macOS 26 (Liquid Glass). Respect light/dark, accent color, reduced-motion, reduced-transparency.
2. **Additive, not hostile.** Never fight the system Dock; coexist by default, replace only on explicit opt-in.
3. **Invisible until intentional.** A Dock should feel like it *belongs* to a desktop. No surprise windows, no focus theft, no flicker.
4. **One core gesture.** "Pin this Dock here" is the hero action; everything else is configuration.

## 2. Information architecture

```
Menu-bar status item  (always present, the only system-visible chrome)
 ├─ ▸ Desktop 3 — 2 docks active        (current-space readout)
 ├─ Docks
 │    ├─ ◉ Dev        (toggle)   ⤷ pinned: Desktop 3 · Displays A,B
 │    ├─ ◉ Comms      (toggle)   ⤷ pinned: Desktop 1
 │    └─ ○ Media      (disabled)
 ├─ Pin a dock here…              (one-click bind to current space)
 ├─ Peek all docks   (⌥-hold)
 ├─ Settings…  (⌘,)
 └─ Quit
```

Main **Settings** window (SwiftUI, source-list layout):

```
┌ Sidebar ────────┬ Detail ─────────────────────────────────────┐
│ ◉ Dev           │  [ Items | Pinning | Appearance | Behavior ] │
│ ◉ Comms         │                                              │
│ ○ Media         │   …tab content…                              │
│ + New Dock      │                                              │
├─────────────────┤                                              │
│ General         │                                              │
│ Shortcuts       │                                              │
│ Permissions     │                                              │
│ About / Updates │                                              │
└─────────────────┴──────────────────────────────────────────────┘
```

### 2.1 "Pinning" tab (the core UX)
A live, visual Space picker:

```
 Where should “Dev” appear?

  ( ) Follows me (current desktop only)
  ( ) Every desktop
  (•) Specific desktops:

     Display A (Built-in)        Display B (LG UltraFine)
     ┌──┐ ┌──┐ ┌──┐ ┌──┐         ┌──┐ ┌──┐
     │ 1│ │ 2│ │▣3│ │ 4│         │ 1│ │ 2│
     └──┘ └──┘ └──┘ └──┘         └──┘ └──┘
              ▲ selected = pinned here

  ☐ Also show over fullscreen apps
  [ Pin to the desktop I'm on now ]   ← hero button
```
- Desktop tiles are rendered live from `SLSCopyManagedDisplaySpaces`; the current desktop is highlighted; clicking a tile toggles membership.
- With **DHSS OFF**, the picker collapses to a single row of desktops (since Spaces span displays) plus a separate "show on displays: ☑A ☑B" control — directly mirroring the technical topology so the mental model matches reality.
- The hero button "Pin to the desktop I'm on now" is the 1-click path most users take.

## 3. The Dock surface visual design

### 3.1 Styles
| Style | Look | Implementation |
|------|------|----------------|
| **Liquid Glass** (default on macOS 26) | Translucent glass slab w/ specular edge | `NSGlassEffectView` / SwiftUI `.glassEffect()` |
| **Classic** | Frosted `NSVisualEffectView` (.hudWindow / .dock) | AppKit material |
| **Solid** | Opaque rounded panel, tintable | CALayer fill |
| **Minimal** | Icons only, no background slab | transparent panel |

Adapts automatically to reduced-transparency (→ Solid) and increased-contrast.

### 3.2 Geometry & layout
- Orientations: bottom / top / left / right / floating island.
- Icon sizes 24–128 px; hover magnification curve identical-feeling to the system Dock (Gaussian falloff over neighbors), togglable.
- Running indicator: a small dot/line under/next to running apps; active app slightly brighter.
- Separators and spacers for grouping; folder stacks open as fan / grid / list popovers anchored to the icon.
- Multi-monitor (DHSS off): identical Dock mirrored per chosen display, each positioned on that display's edge.

### 3.3 Motion
- Reveal/hide: spring slide from the bound edge (respects Reduce Motion → cross-fade).
- Item launch: subtle bounce (togglable), matching system Dock affordance.
- Magnification: CADisplayLink-driven, capped to display refresh; disabled under Low Power / Reduce Motion.

## 4. Interaction details
- **Left-click** app → launch or activate (never steals key focus from current app; activation is the target app's).
- **Right-click** item → contextual menu (Options, Remove, Reveal in Finder, Open at Login, Keep in Dock).
- **Drag** an app/file from Finder onto a Dock → add item; drag within → reorder; drag out → remove (poof).
- **⌥-hover** → quick actions; **⌘-click** → reveal in Finder.
- **Hot corners / edge** → auto-hide reveal.
- Keyboard: a global hotkey can focus a Dock for arrow-key navigation + Return to launch (accessibility + power-user).

## 5. Onboarding (first run)
1. Welcome → one sentence on what Dockman does.
2. "Let's make your first Dock" → prefilled with the user's current system-Dock apps (read from `com.apple.dock` `persistent-apps`, read-only) as a friendly starting point.
3. "Pin it to this desktop" → performs the hero action live so the user *sees* it work.
4. Optional toggles: start at login (`SMAppService`), hide the system Dock.
5. Permissions are requested **lazily** — only when the user enables a feature that needs them (Accessibility for keyboard-nav/window features; Screen Recording is never requested in v1).

## 6. Accessibility
- Full VoiceOver labels on every Dock item (`NSAccessibility`), even though items live in a borderless panel.
- Honors Reduce Motion, Reduce Transparency, Increase Contrast, Differentiate Without Color (indicators get shape, not just color).
- Keyboard-navigable Docks; Dynamic-Type-aware labels in popovers/settings.
- Minimum hit targets ≥ 24×24 pt regardless of icon scale.

## 7. Empty/edge states
- No Docks yet → settings shows a friendly "Create your first Dock" zero-state.
- Binding orphaned (Space deleted) → a gentle banner on the parked Dock: "Desktop for 'Dev' was removed — re-pin?" with a one-click fix.
- Fallback mode active (private API unavailable) → a one-time, dismissible notice explaining the minor switch-flicker, with a "Learn more" to diagnostics.
- Single display / DHSS unknown → picker hides display columns automatically.

## 8. Branding
- Name: **Dockman**. Bundle id: `xyz.waqas.dockman`.
- App is `LSUIElement`: no system-Dock icon of its own (it *makes* Docks; it doesn't sit in one). Identity lives in the menu-bar item + settings window.
- Status-item glyph: a minimal "stacked tiles" mark; monochrome template image so it tints with the menu bar.
