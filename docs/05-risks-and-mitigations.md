# 05 — Risks, Failure Modes & Mitigations

Each risk: **likelihood × impact**, the failure it produces, and a concrete mitigation already designed into the architecture.

---

## R-1 · Private SkyLight symbols change or disappear in a future macOS
**Likelihood: Medium · Impact: High (core feature breaks).**
SkyLight is undocumented; Apple can rename/remove/re-gate `SLS*` symbols (they tightened things in 14.5 already).

**Mitigations**
- Symbols bound at runtime via `dlopen`/`dlsym`, trying `SLS*` then legacy `CGS*` names. A missing symbol is a recoverable condition, not a crash.
- `SkyLightSpacesService` publishes a `capabilities` set; if core mutators are absent the app swaps in `FallbackSpacesService` (public `.canJoinAllSpaces` + manual hide/show) and shows a one-time notice.
- All private use isolated to one module (`SpacesKit/SkyLightShim`) → small, well-tested blast radius.
- `SpacesContractTests` run on real hardware in CI per macOS beta to catch ABI drift **before** users do.
- Maintain a per-OS capability matrix in-repo; gate features on it.

---

## R-2 · The macOS 14.5 `connection_holds_rights_on_window` tightening
**Likelihood: N/A (already happened) · Impact: would be fatal if we mis-scoped.**
This is the change that forced yabai to require SIP-off.

**Mitigation (by design, not patch):** Dockman only ever moves **its own** windows, on which its connection inherently holds rights. The mutating call set is funneled through one method guarded by an `ownsWindow(wid)` assertion (technical design §3.4). We never touch foreign windows, so the rights check is always satisfied and SIP stays enabled. This constraint is the product's foundation, encoded as an invariant.

---

## R-3 · Managed Space IDs not stable across reboot / Space reorder
**Likelihood: High · Impact: Medium (Docks land on the wrong desktop).**

**Mitigations**
- Composite binding key: `spaceUUID` → `spaceID` → ordinal `(displayUUID, spaceIndex)` fallback (technical design §5).
- `BindingResolver` re-resolves on every `SLSCopyManagedDisplaySpaces` diff and on login.
- `OrphanHandler` parks unresolved Docks on the current Space and offers one-click re-pin instead of silently vanishing.

---

## R-4 · Window flicker / wrong Space on switch
**Likelihood: Medium · Impact: Medium (looks broken).**
If we relied on hide/show per switch, fast switching would flicker.

**Mitigations**
- Primary mechanism is **pre-assignment** via SkyLight: the WindowServer shows/hides the window with zero Dockman involvement on the hot path → no flicker by construction.
- The flicker-prone path exists *only* in fallback mode; there we pre-warm both states and cross-fade, and debounce rapid switches (50 ms coalescing) to avoid thrash.
- `collectionBehavior` tuned (`.stationary`, no `.managed` auto-relocation) so WindowServer doesn't fight our placement.

---

## R-5 · `collectionBehavior` ⊕ manual SkyLight placement interact unexpectedly
**Likelihood: Medium · Impact: Medium.**
Some behavior flags (`.managed`, `.canJoinAllSpaces`) cause WindowServer to *auto-move* windows, conflicting with explicit placement.

**Mitigations**
- Documented, tested combination: `[.stationary, .ignoresCycle, .fullScreenAuxiliary]` and **never** `.canJoinAllSpaces` in pinned mode.
- Phase-0 spike empirically validates the flag combo on macOS 14/15/26 before building on it; results recorded in the capability matrix.

---

## R-6 · Focus theft / clicking a Dock activates Dockman
**Likelihood: Medium · Impact: High (ruins the "extra dock" feel).**

**Mitigations**
- `NSPanel` with `.nonactivatingPanel`, `canBecomeKey=false`, `canBecomeMain=false`.
- App is `LSUIElement` (no activation policy that grabs focus).
- Item launches use `NSWorkspace.openApplication`/`runningApp.activate` so the *target* app becomes active, never Dockman.
- Covered by AC-5 acceptance test.

---

## R-7 · Cannot reserve screen space like the real Dock
**Likelihood: High (it's a known platform limit) · Impact: Medium (user expectation gap).**
Maximized windows can slide under an overlay Dock.

**Mitigations**
- Default model is **overlay + auto-hide**, which makes the limitation a non-issue for most users.
- Set expectations in onboarding copy ("Dockman floats above your windows").
- Reservation kept as a clearly-labeled **experimental** toggle; treated as a research spike, never a v1 promise (technical design §7).

---

## R-8 · Fullscreen apps show/hide the Dock incorrectly
**Likelihood: Medium · Impact: Medium.**

**Mitigations**
- Docks are simply never assigned to `type==2` (fullscreen) Spaces ⇒ they vanish in fullscreen automatically.
- Opt-in "show over fullscreen" sets `.fullScreenAuxiliary` and assigns to the fullscreen Space ID as it appears; re-evaluated on each Space-set diff.

---

## R-9 · Display hot-plug / resolution / arrangement changes
**Likelihood: High · Impact: Medium (ghost or mis-placed Docks).**

**Mitigations**
- Listen to `didChangeScreenParameters` + `CGDisplayReconfigurationCallback`; full reconcile (destroy gone-display windows, create new-display windows, reposition, re-pin).
- Bindings keyed by **display UUID** (stable), not `CGDirectDisplayID` (session-scoped).
- Coalesce the storm of reconfigure callbacks (debounce) to reconcile once per settle.

---

## R-10 · DHSS toggled by the user (on↔off)
**Likelihood: Low · Impact: Medium.**
Changing DHSS requires logout, but the topology then differs fundamentally (per-display stacks vs one global stack).

**Mitigations**
- Detect topology authoritatively each launch via `SLSCopyManagedDisplaySpaces` shape (single `"Main"` vs per-display), not a cached assumption.
- Binding model stores both a Space key and a display set, so it remains meaningful under either topology; resolver adapts.

---

## R-11 · High CPU / battery drain
**Likelihood: Medium · Impact: High (reputation killer for a background agent).**

**Mitigations**
- **Notification-driven, zero busy-poll.** Work happens only on real events (space change, display change, wake, launch/terminate).
- Magnification animation gated by `CADisplayLink`, paused when idle / Low Power / Reduce Motion.
- Icon decoding cached; off-main; layers rasterized.
- Perf budget enforced in CI soak test (AC-6: < 0.5% idle CPU).

---

## R-12 · Notarization / Gatekeeper rejection due to private API
**Likelihood: Low for notarization, High for Mac App Store · Impact: High if misjudged.**
Notarization is automated malware scanning, **not** API review — private API use does **not** block notarization. MAS review **does** inspect for private API and would reject.

**Mitigations**
- Ship v1 as Developer-ID-signed + notarized **outside** MAS (no API review). Hardened runtime, no special entitlements needed.
- Keep `dlsym` indirection (no static `_SLS*` symbols in the binary's import table) — also reduces static-analysis flags.
- Reserve a future MAS "lite" build that compiles out the SkyLight path entirely (FallbackSpacesService only).

---

## R-13 · Permissions friction (Accessibility / Screen Recording)
**Likelihood: Medium · Impact: Medium (drop-off at setup).**

**Mitigations**
- Core pin/launch features need **no** special permission. Request nothing at first run.
- Accessibility requested **lazily**, only when the user enables keyboard-navigation/window features, with an in-app coach explaining why.
- Screen Recording not used in v1 (no live previews) → not requested at all.

---

## R-14 · Mission Control shows duplicate/odd Dock thumbnails
**Likelihood: Medium · Impact: Low (cosmetic).**
A window assigned to a Space appears in that Space's Mission Control thumbnail; multi-Space bindings appear in several.

**Mitigations**
- `.stationary` + dock-level windows minimize disruption.
- Option to set windows non-thumbnail via window sharing/`SLSSetWindowListExcludeFromMissionControl`-style exclusion **if** available (capability-gated); otherwise accept as cosmetic and documented.

---

## R-15 · Race conditions on rapid Space switching / WindowServer IPC threading
**Likelihood: Medium · Impact: Medium (placement glitches, rare crashes).**

**Mitigations**
- All WindowServer/`NSWindow`/`CALayer` work pinned to `@MainActor`; SkyLight IPC serialized.
- Debounce via cancellable main-actor `Task`, not overlapping timers.
- Idempotent reconcile: placement is computed from desired-state vs `SLSCopySpacesForWindows` actual-state, so repeated/late events converge rather than corrupt.

---

## R-16 · Data loss / corrupted config
**Likelihood: Low · Impact: High (user loses all Docks).**

**Mitigations**
- Atomic writes; keep last-good backup (`config.json.bak`) and N rotating snapshots.
- Schema-versioned, forward-only migrations with a dry-run validate before replacing.
- Export/import + "reset to defaults" recovery path.
- Security-scoped bookmarks for file/folder items so they survive moves/sandbox.

---

## R-17 · System Dock auto-hide left in a bad state on crash
**Likelihood: Low · Impact: Medium (user's real Dock disappears).**
If we hid the system Dock and crashed, the user might think their Dock is gone.

**Mitigations**
- Only ever change the *documented* `com.apple.dock autohide` pref, and record that we changed it.
- Restore on quit; on next launch, detect "we left autohide on" via our own marker and offer to restore.
- A menu-bar item + a fail-safe "Restore system Dock" command always available.

---

## R-18 · macOS 27+ design/behavior shifts (Liquid Glass evolves, Spaces internals move)
**Likelihood: Medium · Impact: Medium.**

**Mitigations**
- Visual styles abstracted behind a `DockStyle` protocol; glass is one implementation, easily updated.
- Capability matrix + contract tests catch behavioral drift each beta cycle.
- Conservative reliance on the most-stable SLS calls (read-only topology + the long-lived add/move/remove trio used by many shipping tools for a decade).

---

## R-19 · Antivirus / MDM flags an agent doing WindowServer IPC
**Likelihood: Low · Impact: Medium (enterprise deployment friction).**

**Mitigations**
- Proper Developer-ID signature + notarization establishes provenance.
- Public docs page explaining exactly what private calls are made and why (transparency for security teams).
- No network calls except the signed Sparkle update feed (documented endpoint).

---

## R-20 · Accessibility/VoiceOver can't reach borderless-panel items
**Likelihood: Medium · Impact: Medium (compliance + usability).**

**Mitigations**
- Explicit `NSAccessibility` element tree on the Dock layer; each item is a first-class a11y element with role/label/action.
- Keyboard navigation path independent of mouse; tested with VoiceOver in CI manual matrix.

---

## Cross-cutting safety nets
- **Kill switch:** a UserDefaults flag forces FallbackSpacesService (no private calls) for field triage.
- **Self-diagnostic:** "Export Diagnostics" bundles topology snapshot + redacted logs + capability matrix for bug reports.
- **Phase-0 spike gate:** none of the above is assumed — Phase 0 (roadmap) empirically validates the SkyLight behavior on macOS 14/15/26 before full build-out.
