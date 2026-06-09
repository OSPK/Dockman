# 09 — Dock Targeting UI (move a Dock to any Monitor / Space)

How the menu-bar item lets a user send a Dock to any **monitor** and any **desktop
(Space)** — correctly, even when the menu bar itself only exists on one monitor.

---

## 1. The problem, stated precisely

A Dockman Dock's location is **two independent-ish axes**:

1. **Space** — which virtual desktop.
2. **Monitor** — which physical display.

How these axes relate depends on the **"Displays have separate Spaces" (DHSS)** setting:

| | Space ↔ Monitor relationship | Menu bar |
|---|---|---|
| **DHSS ON** | **Coupled.** Each monitor owns its *own* stack of Spaces. Picking a Space implies a monitor. | One per monitor |
| **DHSS OFF** | **Orthogonal.** One Space spans *all* monitors. A Dock can be on Space 3, shown on monitor 2 only. | **Only on the main monitor** |

The hard case (the user's concern): **DHSS OFF with multiple monitors.** There is a
single menu bar — on the main monitor — yet the user may want to place a Dock on a
*different* monitor they are not pointing at. A flat "Move to Monitor 2" text item is
hostile here: monitor names ("LG UltraFine") don't tell you *where* the screen is, and
the control lives somewhere other than the target.

## 2. Design principle: **spatial, not positional**

You should target a monitor by pointing at a **picture of it in its real-world position**,
not by moving your cursor onto it. So the picker is built around a **monitor mini-map**
(the same mental model as System Settings ▸ Displays): rectangles laid out proportionally
to the actual display arrangement, each with a big ordinal ① ② ③.

Three reinforcing cues remove all ambiguity about which tile is which screen:

1. **Spatial layout** — the left tile is the left screen, the upper tile the upper screen.
2. **Identify overlay** — hovering a tile flashes a large number on the *physical* screen
   it represents (Apple's "Identify" pattern). On open, all monitors flash their number
   for ~1.2 s so the user learns the mapping instantly. This is what fully decouples
   "where the control is" from "what it targets."
3. **Live result + toast** — committing moves the Dock immediately. If the target is the
   visible desktop you see it land; if it's a desktop you're not on, a toast confirms
   "Moved *Dev* → Desktop 3 · Monitors ①②".

## 3. The picker adapts to the topology (and teaches it)

A one-line explainer at the top names the current topology, so the UI *teaches* the very
subtlety that causes confusion:

- **DHSS OFF:** *"Desktops span all monitors. Pick a desktop, then the monitors to show on."*
  - **Monitor map = multi-select** (checkbox semantics): which screens display the Dock.
  - **Desktop strip = single-select**: one shared row of desktops 1…N.
  - Result → `Binding(mode:.spaces, spaces:[ref], displayUUIDs:[chosen monitors])`.
    Empty monitor selection = all monitors. (Maps directly to "one window per chosen
    screen on the shared Space", docs/02 §3.3.)

- **DHSS ON:** *"Each monitor has its own desktops. Pick a monitor, then its desktop."*
  - **Monitor map = single-select** (master).
  - **Desktop strip** = the selected monitor's own Spaces (detail).
  - Result → `Binding(mode:.spaces, spaces:[ref to that Space], displayUUIDs:[that monitor])`.

In both modes an **"All desktops"** toggle switches to `Binding.allSpaces` (public
`canJoinAllSpaces` path), still constrained to the chosen monitors.

## 4. Anatomy of the surface

```
┌──────────────────────────────────────────────┐
│ Move “Dev”                                     │  ← dock name (+ switcher if >1 dock)
│ Desktops span all monitors. Pick a desktop,    │  ← topology explainer (adapts)
│ then the monitors to show on.                  │
│                                                │
│ Currently: Desktop 1 · Monitors ①②③           │  ← current binding readout
│                                                │
│ Show on these monitors                         │
│   ┌──────┐   ┌────┐                            │
│   │  ①   │   │ ②  │   ┌─③─┐                     │  ← MonitorMapView: proportional,
│   │ Main │   │    │   └───┘                     │     hover → identify flash on screen,
│   └──────┘   └────┘                            │     click → (multi|single) select
│                                                │
│ Desktop                                        │
│   [1] [2] (3) [4]   + New Desktop…             │  ← SpaceStrip: current marked, click select
│                                                │
│ ☐ Show on all desktops                         │
│                                                │
│        [ Pin to Current Desktop ]   [ Done ]   │
└──────────────────────────────────────────────┘
```

- Hosted in an **`NSPopover`** anchored to the status-item button (so it appears on the
  menu-bar monitor — fine, because the *map* depicts all monitors). The app briefly
  `activate`s so the controls are clickable; the popover is `.transient` and closes on
  outside click.
- Reached from the menu: each Dock's submenu gets **"Move Dock…"**; quick one-click
  actions (*Pin to Current Desktop*, *Show on All Desktops*) remain in the menu for speed.

## 5. Edge cases handled

| Case | Behavior |
|------|----------|
| Single monitor | Monitor map hidden; only the desktop strip shows. |
| Single desktop | Desktop strip shows one tile; monitor map is the main control. |
| Monitor unplugged while open | Popover rebuilds on `didChangeScreenParameters`; stale selections dropped. |
| Dock's current monitor gone | Shown as "(disconnected)"; choosing a new target re-homes it. |
| Fullscreen Spaces | Excluded from the desktop strip (Dockman never pins to type-2 Spaces). |
| Targeting a desktop you can't see | Move still applies; toast confirms; identify overlay helps you pick the right screen. |
| Active space is the target | You see the Dock land immediately. |

## 6. Why not just submenus?

`Move to Space ▸ …` / `Move to Monitor ▸ …` submenus fail the core requirement: they
convey neither spatial arrangement nor the DHSS coupling, and they make the orthogonal
(DHSS-off) case feel like two unrelated lists. The map unifies both axes into one glance
and — via identify — makes an off-screen monitor as easy to target as the one you're on.

## 7. Pure core (testable without a GUI)

The selection→`Binding` mapping is a pure function, `DockTargeting.binding(...)`, unit
tested for both DHSS states (`DockKitTests`). The view is a thin shell over it, so the
logic that actually changes a Dock's home is verified independently of AppKit.
