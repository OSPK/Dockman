# 08 — Building, Testing & Deploying (this machine)

Concrete, copy-pasteable instructions verified against the development machine:
**macOS 26.5.1 (Tahoe) · Apple Silicon (arm64) · Xcode 26.1 · Swift 6.2.1**.

The project is a Swift package. Phase 0 (the feasibility spike) is built and run with
`swift` directly; later phases that need a code-signed agent `.app` use the packaging
script in `scripts/`.

---

## 0. Prerequisites

| Need | Check | Install |
|------|-------|---------|
| Xcode + toolchain | `xcodebuild -version` → `Xcode 26.1` | App Store / developer.apple.com |
| Command-line tools selected | `xcode-select -p` → `/Applications/Xcode.app/Contents/Developer` | `sudo xcode-select -s /Applications/Xcode.app` |
| Swift | `swift --version` → `6.2.1` | bundled with Xcode |
| (Deploy only) Developer ID cert | `security find-identity -v -p codesigning` | Apple Developer Program → "Developer ID Application" |
| (Deploy only) Notary credentials | see §6 | App Store Connect API key |

A **GUI login session is required** to run the spike — it talks to the WindowServer.
Run it from Terminal/this session while logged into the desktop, not over a headless SSH.

---

## 1. Build

```bash
cd /Users/waqas/web/dockman

swift build                 # debug
swift build -c release      # optimized
```

Artifacts land in `.build/debug/` or `.build/release/`.

---

## 2. Test

```bash
swift test                  # runs SpacesKitTests (symbol resolution + topology parsing)
```

These are **contract smoke tests** against the real SkyLight; they must run in a GUI
session (docs/03 §8). Re-run them first whenever a new macOS beta is installed — they
are the early-warning for SkyLight ABI drift (docs/05 R-1).

---

## 3. Run the Phase-0 spike (the gate)

Round-trip validation, then exit:

```bash
swift run dockman-spike -- --once
# or: ./.build/debug/dockman-spike --once
```

Expected on this machine (DHSS off, 3 desktops):

```
Capabilities resolved: readTopology, readWindowSpaces, moveWindows, addRemoveWindows, spaceType
"Displays have separate Spaces" is OFF (spans-displays): true
✅ PASS 1/2 — own window pinned to current Space …
✅ PASS 2/2 — dock now lives on Space … only (a desktop we are not viewing).
```

Interactive (visual) validation — a blue dock appears; switch desktops with
**Ctrl+→/Ctrl+←** and confirm it shows on only one:

```bash
swift run dockman-spike          # Ctrl-C to quit
```

Exit code is `0` only when both round-trip checks pass — usable as a CI gate.

---

## 4. Package as an agent `.app` (local)

The script wraps the built binary in a proper `LSUIElement` bundle and ad-hoc signs it
so it runs as a faceless agent (no system-Dock icon) on this machine:

```bash
./scripts/make-app.sh release        # produces build/Dockman-Spike.app
open build/Dockman-Spike.app         # launches the agent; blue dock appears
```

Ad-hoc signing (`codesign -s -`) is fine for running on the same machine. For
distribution to other Macs you need Developer-ID signing + notarization (§5–§7).

---

## 5. Code signing (Developer ID — for distribution)

List identities:

```bash
security find-identity -v -p codesigning
```

Sign the bundle, inside-out, with the hardened runtime (required for notarization):

```bash
APP="build/Dockman-Spike.app"
IDENTITY="Developer ID Application: Your Name (TEAMID)"

# Sign nested frameworks/helpers first if present, then the app:
codesign --force --options runtime --timestamp \
         --sign "$IDENTITY" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
```

Notes:
- **No special entitlements** are required — SkyLight access on our own windows needs none.
- **App Sandbox stays OFF** for the Developer-ID build (incompatible with SkyLight). Do
  not add `com.apple.security.app-sandbox`.
- Keep the `dlsym` indirection: no static `_SLS*` symbols appear in the import table,
  which also keeps static scanners quiet (docs/05 R-12).

---

## 6. Notarization

Notarization is automated malware scanning, **not** API review, so private-API use does
not block it. `notarytool` ships inside Xcode (`xcrun notarytool`).

One-time: store credentials in a keychain profile (using an App Store Connect API key):

```bash
xcrun notarytool store-credentials "DOCKMAN_NOTARY" \
      --key   "/path/to/AuthKey_XXXX.p8" \
      --key-id "XXXXXXXXXX" \
      --issuer "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

Package, submit, wait, staple:

```bash
# Zip (or build a DMG) for submission
ditto -c -k --keepParent "build/Dockman-Spike.app" "build/Dockman-Spike.zip"

xcrun notarytool submit "build/Dockman-Spike.zip" \
      --keychain-profile "DOCKMAN_NOTARY" --wait

# On success, staple the ticket to the .app (and to the DMG if you ship one)
xcrun stapler staple "build/Dockman-Spike.app"

# Verify Gatekeeper acceptance
spctl -a -vvv -t install "build/Dockman-Spike.app"   # → "accepted, source=Notarized Developer ID"
```

---

## 7. Distribute

- Build a DMG containing the (signed, stapled) `.app`, sign + notarize + staple the DMG too.
- Ship updates via **Sparkle 2** with an EdDSA-signed appcast over HTTPS (docs/06 §4).
- The update check is the app's only outbound network call.

---

## 8. Run at login (full app, later phases)

The shipping app registers itself with `SMAppService.mainApp.register()` and exposes a
toggle in Settings. For the spike you can add it manually under
System Settings ▸ General ▸ Login Items, or just `open` it.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|--------|-------|-----|
| `window has no WindowServer number` | No GUI session (headless SSH) | Run from the desktop session |
| `could not resolve SkyLight topology symbols` | SkyLight symbol renamed (future OS) | App auto-falls-back; file a capability-matrix update (R-1) |
| Pin reads back empty | `moveWindows` capability absent | Check `capabilities` line; fallback mode engaged |
| Dock visible on every desktop | `.canJoinAllSpaces` left set | Ensure pinned mode uses `[.stationary, .ignoresCycle, .fullScreenAuxiliary]` only |
| Gatekeeper "cannot be opened" on another Mac | Not notarized/stapled | Complete §6 |
| `spctl` shows "rejected" | Hardened runtime / timestamp missing | Re-sign with `--options runtime --timestamp` |
| Two docks fighting | Two instances running | Single-instance guard (full app); `killall dockman-spike` |

---

## 10. CI outline (GitHub Actions, macOS runner)

```
jobs:
  build-test:
    runs-on: macos-26
    steps:
      - checkout
      - run: swift build -c release
      - run: swift test            # contract tests need the runner's GUI session
      - run: ./.build/release/dockman-spike --once   # gate: exits non-zero on failure
  notarize:           # tag builds only; needs signing secrets
      - ./scripts/make-app.sh release
      - codesign … && notarytool submit … --wait && stapler staple …
```
