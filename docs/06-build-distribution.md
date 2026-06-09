# 06 — Build, Signing & Distribution

## 1. Build configuration
- **Xcode project**, Swift 6, deployment target macOS 14.0, archs `arm64` + `x86_64` (universal) — though primary QA target is `arm64` on macOS 26.
- App is an **agent**: `Info.plist` `LSUIElement = YES`.
- **Hardened Runtime: ON** (required for notarization).
- **App Sandbox: OFF** for v1 (incompatible with SkyLight IPC; not required for Developer-ID distribution).
- No special/private entitlements requested. SkyLight access needs none for own-window operations.
- `NSScreenCaptureUsageDescription` etc. omitted in v1 (no Screen Recording). `NSAppleEventsUsageDescription` only if Action items use AppleScript.

## 2. Why not the Mac App Store (v1)
1. **Private API use** — MAS review statically/dynamically inspects for private symbols and rejects them. Our `dlsym` indirection avoids an import-table giveaway but is not a license to ship private behavior on MAS.
2. **No App Sandbox** — MAS requires it; SkyLight + global hotkeys + cross-app launching chafe against the sandbox.

**Decision:** Developer-ID distribution. A future **"MAS-lite"** target can compile out `SkyLightSpacesService` (build flag `DOCKMAN_PUBLIC_ONLY`) leaving only `FallbackSpacesService` — sandbox-clean, no private API — accepting reduced fidelity (per-switch hide/show, no hard pin).

## 3. Signing & notarization pipeline
```
1. Build universal Release archive (xcodebuild archive)
2. Code sign with "Developer ID Application: <Team>" + hardened runtime + secure timestamp
3. Sign embedded frameworks (Sparkle) and the XPC/login helper, inside-out
4. Create DMG (or zip) containing Dockman.app
5. Notarize:  xcrun notarytool submit Dockman.dmg --wait
6. Staple:    xcrun stapler staple Dockman.dmg  (and the .app)
7. Verify:    spctl -a -vvv -t install Dockman.app   → "accepted, source=Notarized Developer ID"
```
- Notarization is **automated malware scanning, not API review** → private-API use does not block it (see R-12).
- CI (GitHub Actions on macOS runners) runs steps 1–7; secrets via encrypted keychain + App Store Connect API key for `notarytool`.

## 4. Auto-update
- **Sparkle 2** with an EdDSA-signed appcast over HTTPS.
- Update feed is the app's only outbound network call; endpoint documented for security teams (R-19).
- Delta updates optional; full DMG fallback always.
- Respect "check automatically" preference; never auto-install without consent for an agent that manipulates the desktop.

## 5. Login item & lifecycle
- Auto-start via `SMAppService.mainApp.register()` (ServiceManagement), toggle in Settings → General.
- Single-instance guard (named lock / `NSRunningApplication` check) to prevent two agents fighting over the same Dock windows.
- Clean teardown on quit: restore system-Dock autohide if we changed it (R-17), remove all Dock windows, unregister hotkeys/event taps.

## 6. Versioning & release channels
- SemVer; `CFBundleShortVersionString` user-facing, `CFBundleVersion` monotonic build number.
- Channels: **Stable** and **Beta** (separate appcasts). Beta auto-enrolls for each macOS major beta to catch SkyLight drift early.

## 7. Telemetry & privacy
- **No analytics/telemetry in v1** by default. If added later: opt-in only, no PII, documented.
- Crash reporting: opt-in (e.g., self-hosted or Apple's), symbolicated; redact file paths in diagnostics exports.
- Privacy policy: app reads system Dock prefs (read-only), running apps, and user-chosen files; nothing leaves the device except the update check.

## 8. QA matrix (gating release)
| Axis | Values |
|------|--------|
| macOS | 14.x, 15.x, 26.x |
| Silicon | Apple Silicon (primary), Intel (best-effort) |
| Displays | 1, 2 (mixed DPI), unplug/replug |
| DHSS | ON, OFF |
| Spaces | create/delete/reorder during runtime, fullscreen enter/exit |
| Power | wake from sleep, Low Power Mode |

Release blocks on AC-1…AC-8 (product spec §5) passing across the bolded core cells, plus a 72-hour soak (R-11/R-15).
