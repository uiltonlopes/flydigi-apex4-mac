# Roadmap and status

What is done, what still needs a test on hardware, and what is left. Feature-by-feature parity with
Flydigi Space Station 4 (Windows) for the Apex 4 is the baseline; everything below "Beyond" is ours.
Legend: ✅ verified on hardware · 🧪 implemented, needs a hardware test · ❌ not done · 🚫 not on macOS.

## Done (parity with Space Station 4 for the Apex 4)

- ✅ Transports: DInput HID directly (no privileges), XInput through the `SMAppService` helper (IOUSBLib capture), USB-C and the charging base's 2.4 GHz receiver (waiting state while the pad is off, reconnection, battery over the receiver).
- ✅ Profiles: the 4 on-board slots, the slot the pad itself selected is respected (fast swap, screen menu), rename, apply/revert, restore default configuration, per-slot lighting, "Apply to NS mode" (Switch slots 4–7), local library with `.fdgprofile` export/import.
- ✅ General: lighting modes Default / Steady / Breathing / Gradient / Off with per-mode colour limits, brightness and cycle time applied live; grip vibration with test; sleep time, fast swap config, Turbo hardware shortcut.
- ✅ Buttons: click / turbo / macro / special per key with "press it on the pad" capture (paddles included).
- ✅ Sticks: SS4's sensitivity curve (Default / Instant / Delay / Custom with draggable nodes, live dot), dead zone, edge, report-rate meter, circularity test, guided calibration.
- ✅ Gyro: mapping, activation key and second key, sensitivity, dead zone, use mode.
- ✅ Triggers: ForceAdapt General / Racing / Recoil / Sniper / Trigger lock / Vibration with SS4's parameters, the pad's own presets as defaults, live preview while dragging, vibration test.
- ✅ Macros: on-board macros with step editor, recording from the pad, local library with `.fdgmacro` export/import. Verified on hardware 2026-09-04: recorded on M1, played back by the pad, edited and played again.
- ✅ Screen: image/GIF editor (pan, zoom, fit/fill, trim, frame interval sent to the pad), Flydigi's animation library, factory animations, GIPHY search, "on the controller" record, restore default animation.
- ✅ Per-app game profiles: slot + ForceAdapt + lighting switched when the chosen app comes to the front and restored when it leaves (verified with Safari as the target app, 2026-09-04).
- ✅ Share codes compatible with Space Station (2026-09-04): profile menu › Share as code… / Import from code…, `apex4 config share-code --upload` / `import-code`. Bean ↔ blob port of `MappingConfigParserV30` plus a small protobuf codec; verified against Flydigi's service with a real upload and download. Macro share codes (decimal-dash `MacroItem`) are still file-only.
- ✅ Keyboard / mouse mapping (2026-09-04): Special buttons → key / left or right click / wheel, sticks → keyboard (4 or 8 directions) or mouse, gyro → mouse. App-side engine posting CGEvents (Accessibility permission), mappings stored per controller and slot on the Mac; buttons need DInput because the firmware hides keyboard-flagged keys from the Xbox report. Verified on hardware: key, clicks, stick → mouse, and gyro → mouse (yaw → X, pitch → Y, signs checked with the pointer; the pad only streams motion while the profile's gyro is on). Gyro aiming works but feels rough — raw rate to pointer, like Space Station's classic path; smoothing/acceleration would be the next step if anyone wants it.
- ✅ Firmware update from the app: Settings › Firmware Update runs the whole sequence (download + validate, switch to DInput through the helper, OTA with progress, wait for the restart, back to XInput). Verified 2026-09-04: CLI 6.8.3.0 → 6.8.3.7, then the app re-flashed 6.8.3.7 end to end ([firmware-update.md](firmware-update.md) §6c).
- ✅ Settings: firmware update check with Flydigi's note, USB mode switch, language (English, Português do Brasil), GIPHY key, open at login, helper install/remove, quit-on-close, log export. Device nickname (right-click the card).
- ✅ App update check (2026-09-04): GitHub releases, once a day and on demand in Settings › About, badge in the sidebar; the DMG opens in the browser.
- ✅ Helper idle exit after 10 minutes (launchd restarts it on the next message).
- ✅ `spacestation://` URL scheme (pages, tab, key, profile slot) for Shortcuts and scripts.
- ✅ Release pipeline: Developer ID signing, notarization and stapling of app and DMG (`scripts/release.sh`).

## Needs a hardware test

- 🧪 **NS mode**: the profile is written to slots 4–7 exactly as Space Station does; nobody on the project owns a Switch, so it stays unverified until an owner reports.
- 🧪 Other Apex 4 editions (device ids 86, 87, 92, 93, 102, 103, 104): same protocol, artwork present, never connected here.

## Open

- ❌ Helper: peer code-signing requirement on macOS 14–15. The Swift `XPCListener` requirement API is macOS 26 only and the C one (`xpc_listener_set_peer_code_signing_requirement`, 14.4+) has no bridge to the Swift listener; on those systems any local process can ask the helper to talk to the controller. Request sizes and ranges are validated, nothing beyond controller commands is exposed.
- ❌ Beyond Space Station: racing telemetry driving trigger resistance (Forza "Data Out", F1, Dirt, WRC); shareable community presets (LED themes, GIF packs, game profiles).

## Not applicable on macOS

- 🚫 Space Station's game mods (DLL injection) and DS / PS5 mode (Windows kernel drivers). Per-app game profiles are our replacement.
- 🚫 Bluetooth configuration: Flydigi's BLE service only covers the BS1 cooler, not the Apex 4.
- 🚫 Screen upload over the 2.4 GHz receiver: the receiver never acks those packets. Cable only.
- 🚫 Joystick global settings, polling rate, vibration light effect, trigger vibration switch: hidden or unsupported for the Apex 4 in Space Station too.
