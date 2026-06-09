# 07 — Roadmap & Phased Delivery

The plan is **de-risk first**: prove the one uncertain thing (private-API space pinning on this exact OS) before building UI on top of it.

---

## Phase 0 — Feasibility spike (the gate) ⛳  ✅ PASSED (macOS 26.5.1, arm64)

> **Result, 2026-06-09 — dev machine (macOS 26.5.1 Tahoe, Apple Silicon):**
> - All SkyLight symbols resolved: `readTopology, readWindowSpaces, moveWindows, addRemoveWindows, spaceType`.
> - **"Displays have separate Spaces" detected OFF** (`spans-displays: true`) — the exact target scenario. Single `"Main"` managed display with user Spaces `[1, 4, 5]`.
> - **PASS 1/2** — pinned our own borderless `NSPanel` to the current Space and confirmed via `SLSCopySpacesForWindows`.
> - **PASS 2/2** — relocated the window to non-current Space `4`; read-back returned exactly `[4]` — i.e. the dock now lives on a desktop we are *not* viewing.
> - All with **SIP enabled, no injection, no special entitlement**, validating the docs/02 §2.2 safety argument on this OS.
> - `swift test` (4 contract tests) green.
>
> Code: `Sources/SpacesKit/*`, `Sources/DockmanSpike/main.swift`. Reproduce: `swift run dockman-spike -- --once`.
> **Still TODO for full Phase-0 closure:** repeat on macOS 14 & 15; repeat with DHSS *ON*; repeat with two physical displays; lock the final `collectionBehavior` combo (R-5).

**Goal: empirically confirm the core mechanism on macOS 14 / 15 / 26 before committing.**

Deliverable: a 200-line throwaway command-line/agent that:
1. `dlopen`s SkyLight, resolves `SLSMainConnectionID`, `SLSCopyManagedDisplaySpaces`, `SLSMoveWindowsToManagedSpace`, `SLSCopySpacesForWindows`, `SLSSpaceGetType`.
2. Creates one borderless `NSPanel`.
3. Prints the Space topology (and whether it's the `"Main"`/DHSS-off shape or per-display).
4. Pins the panel to a chosen Space ID and verifies via `SLSCopySpacesForWindows`.
5. Confirms the panel shows only on that Space when switching desktops — **with SIP enabled**.
6. Repeats with DHSS OFF and with two displays.

**Exit criteria (go/no-go):**
- ✅ Pinning a self-owned window to a specific Space works with SIP on, on macOS 26.5. → proceed.
- ✅ Works with DHSS off across displays.
- ⚠️ If a needed symbol is gated/missing → validate `FallbackSpacesService` (`canJoinAllSpaces` + hide/show) as the floor, and re-scope expectations before Phase 1.

Also lock down in Phase 0: the exact `collectionBehavior` flag combo (R-5), window-level choice, and non-activation behavior.

---

## Phase 1 — Walking skeleton (MVP core)  ✅ IMPLEMENTED (2026-06-09)

> **Result — dev machine (macOS 26.5.1, DHSS OFF, 3 displays):**
> - `ConfigKit` (Config/DockModel/Binding/SpaceRef + atomic ConfigStore w/ backup),
>   `SpacesKit.SpaceMonitor` (notification-driven, no polling), `DockKit`
>   (DockPanel, DockContentView, BindingResolver, DockController), and the
>   `dockman` agent app (status-item menu) are built and running.
> - First run auto-creates a default 5-app dock pinned to the current Space.
> - **AC-1 PASS** — windows pin to the bound Space (verified live via `SLSCopySpacesForWindows`).
> - **AC-2 PASS** — rebinding to a non-current Space moves all dock windows there and they go off-screen on the current desktop (membership `[4]`, `onscreen=false`).
> - **AC-5** — launch path uses a non-activating panel + `.accessory` policy + target-app activation (design-enforced; not yet click-tested under automation).
> - **AC-6** — `SpaceMonitor` is purely notification-driven (no busy-poll); idle-CPU soak not yet measured.
> - Exceeded planned scope on the **multi-display DHSS-OFF** path (one window per
>   screen on the shared Space — 3 windows, all pinned correctly).
> - **Bug found & fixed during bring-up:** this macOS build reports an **empty
>   Space `uuid`**; the resolver's UUID step matched the first empty-UUID Space
>   instead of falling through to `spaceID`. Fixed (empty UUID treated as absent)
>   and a separate race fixed by basing `set()` on the atomic `move-to-exactly`
>   call (docs/05 R-15). Both covered by `DockKitTests`.
> - 14 tests green (`swift test`). Run it: `./scripts/make-app.sh app && open build/Dockman.app`.
>
> **Still TODO for full Phase-1 closure:** human visual confirmation while
> switching desktops; DHSS-ON topology; single-display; AC-5 click test; AC-6 soak.

**Goal: one Dock, pinned to one Space, launches apps. End-to-end, ugly but real.**
- `SpacesKit`: `SpacesService` protocol, `SkyLightSpacesService`, capability detection, `SpaceTopology`, `SpaceMonitor`.
- `DockKit`: `DockPanel`, minimal `DockLayerRenderer` (icons + click-to-launch), `DockController` (windows per display).
- `ConfigKit`: load/save one `Config`.
- "Pin here" via menu-bar status item.
- **Acceptance:** AC-1, AC-2, AC-5, AC-6 pass on macOS 26, single display, DHSS on.

---

## Phase 2 — Resilience  ✅ IMPLEMENTED (2026-06-09)

> **Result — dev machine (macOS 26.5.1, DHSS OFF, 3 displays):**
> - **Orphan handling (AC-4) PASS** — when a Dock's bound Space no longer resolves,
>   it is **parked on the current desktop** (stays visible/usable, no crash) and the
>   menu shows "⚠ desktop removed" with a one-click **Re-pin to This Desktop**.
>   Verified by pointing a binding at a non-existent Space: all 3 windows parked on
>   the current Space `[1]`, app healthy.
> - **Launch-churn vs live-delete** — the resolver now reports whether a match was
>   *exact* (uuid/id) or *ordinal*. A Dock that once matched exactly and later misses
>   is treated as orphaned (no silent neighbor-grab); a fresh login where IDs churned
>   still restores via ordinal. Covered by `DockKitTests`.
> - **Fullscreen policy (AC-3)** — pinned Docks are never assigned to fullscreen
>   (type-2) Spaces, so they hide there automatically; all-Spaces Docks `orderOut` on
>   fullscreen unless `behavior.showOverFullscreen`. (Runtime visual check pending.)
> - **Config migration (AC-8)** — schema bumped to v2; `DockModel` decodes tolerantly
>   (legacy configs without `behavior`/`appearance` load with defaults) and
>   `ConfigStore` migrates forward. Covered by `ConfigKitTests`.
> - **Multi-display reconcile (AC-7)** — one window per screen, created/torn down on
>   `didChangeScreenParameters`; stable across repeated relaunches (3/3 windows).
> - 23 tests green. (DHSS-ON topology + physical hot-plug/sleep still need a manual pass.)

**Goal: survive the real world.**
- `BindingResolver` (uuid→id→ordinal) + `OrphanHandler`.
- Display hot-plug, sleep/wake, Space add/remove/reorder reconcile.
- DHSS-OFF multi-display path (windows per display on one global Space).
- Fullscreen hide/show.
- Atomic config + migrations + backup.
- **Acceptance:** AC-3, AC-4, AC-7, AC-8 pass; matrix incl. DHSS off + dual display.

---

## Phase 3 — Multiple Docks & item richness  ✅ IMPLEMENTED (2026-06-09)

> **Result — dev machine (macOS 26.5.1, 3 displays):**
> - **Rich item kinds** — `app`, `file`, `folder` (stack popover), `spacer`,
>   `separator`, `action` (openURL/command), `runningAppsZone`. A demo Dock with all
>   seven rendered with no crash (window 312→1254 px as the zone populated).
> - **Running-apps zone (live)** — dynamic icons for running apps not already pinned;
>   verified live: launching Calculator grew the Dock +1 icon (1194→1254), quitting
>   shrank it back (1254→1194). A 0.25 s debounce fixes the `didTerminate` race.
> - **Running indicators** — dots under apps that are running (driven by `AppActivityMonitor`).
> - **`dockman://` URL scheme** — `toggle`/`pin`/`show`/`hide?dock=NAME`; verified
>   `toggle` live (3 onscreen → 0 → 3). Action items can issue the same commands.
> - **Drag-and-drop** — reorder within a Dock + drop files/apps/folders from Finder to
>   add (classified app/folder/file); **context menu** Open/Reveal/Remove, plus
>   "Keep in Dock" promoting a zone app. Pure list ops unit-tested.
> - **Folder stacks** — grid/list popover of a folder's contents.
> - 31 tests green (item Codable, reorder/insert/remove, running-zone filter, folder
>   enumeration, URL parsing).
>
> **Deferred to Phase 4/later:** global hotkeys; launch-bounce + magnification
> animations; drag-out-to-remove (context-menu Remove covers it). Drag/drop and the
> folder popover are wired but need a human interactive pass.

Originally scoped as:
- N Docks; per-Dock bindings; enable/disable.
- Item kinds: file, folder stack (popover), separator/spacer, action, running-apps zone.
- Drag-and-drop add/reorder/remove; running indicators; launch animations.
- URL scheme + global hotkeys.

---

## Phase 4 — Design & polish  ◐ IN PROGRESS

> **Delivered:**
> - **Per-dock auto-hide** — fades the Dock in place (alpha + mouse-transparency) when
>   the cursor leaves, reveals when it returns to the screen-edge strip. Fades rather
>   than slides, so it never crosses onto an adjacent stacked display.
> - **Per-dock icon size** — Small/Medium/Large/Huge (window resizes to fit; verified
>   52→72, 96→116, 36→56 px).
> - **Per-dock placement** — Bottom/Top (horizontal) and Left/Right (vertical column),
>   anchored to the correct screen edge; never overflows onto another display.
> - **Per-dock visual style** — **Liquid Glass** (macOS 26 `NSGlassEffectView`, falls
>   back to Classic pre-26), **Classic** (frosted), **Solid** (tinted), **Minimal**
>   (no slab, window shadow off). All four verified crash-free at runtime.
> - **Hover feedback** — icons scale up ~18% on hover (respects Reduce Motion).
> - **Over-dock magnification** (per-dock, opt-in) — icons grow with cursor distance via
>   a raised-cosine falloff and pop *above* the bar; the window reserves cross-axis
>   headroom and the background slab is a sibling beneath the icons so they're never
>   clipped. Works on all four edges (grows inward). Falloff curve unit-tested.
> - **SwiftUI Settings window** — sidebar of docks + General pane; live-edits name,
>   enable, style, position, icon size, tint, magnification, behavior, placement.
> - **Hide the system Dock** — `SystemDock` helper with safe restore when turned off.
> - **Reduce Transparency** — translucent styles auto-substitute a Solid slab; live
>   re-render on the accessibility-options-changed notification.
> - **Summon windows** + **Accessibility prompt on launch** (per-dock, opt-in).
> - **Start at Login** — `SMAppService` register/unregister, preference synced on launch;
>   full lifecycle verified (status 0→1 on enable, 1→0 on disable).
> - **Persistence verified** — all settings/positions/styles save atomically on change
>   and restore on restart (round-trip confirmed: a change survives quit+relaunch and is
>   re-applied; e.g. edge=left, iconSize=72 came back as a vertical 92px column).
> - All in the menu-bar ▸ dock submenu (Start at Login is top-level).
>
> **Still to do:** onboarding/first-run flow; VoiceOver pass.

- Settings UI (SwiftUI) — Docks list, visual Space picker, appearance, behavior tabs.
- Styles: Liquid Glass / Classic / Solid / Minimal; magnification; orientations; auto-hide engine.
- Onboarding flow; accessibility/VoiceOver pass; reduced-motion/transparency.
- Hide-system-Dock opt-in with safe restore.

---

## Phase 5 — Distribution hardening
- Developer-ID sign + notarize + staple pipeline in CI.
- Sparkle auto-update; login item; single-instance guard.
- Diagnostics export; kill switch; capability matrix doc.
- 72-hour soak; full QA matrix (macOS 14/15/26 × DHSS × displays).

---

## Phase 6 — Stretch / v2 candidates
- Experimental screen-area reservation spike (R-7).
- Live window previews (needs Screen Recording).
- iCloud/Drive config sync.
- "MAS-lite" public-only build (`DOCKMAN_PUBLIC_ONLY`).
- Shortcuts.app actions, Focus-mode-aware Dock switching, per-Space wallpaper integration.

---

## Critical path & sequencing notes
- **Phase 0 gates everything.** Do not build UI before the spike proves pinning on macOS 26.5.
- `SpacesService` protocol from day one → all higher layers test against `MockSpacesService`, so Phases 1–4 don't need real hardware for unit tests; only `SpacesContractTests` do.
- Keep the private surface frozen and tiny; when a new macOS beta drops, re-run Phase 0 spike + contract tests **first**.

## Estimated shape (relative, not calendar)
| Phase | Relative effort | Risk burned down |
|------:|:---------------:|------------------|
| 0 | XS | The entire core uncertainty |
| 1 | M | End-to-end viability |
| 2 | L | Real-world stability |
| 3 | L | Feature completeness |
| 4 | L | Product quality |
| 5 | M | Shippability |
| 6 | — | Upside |
