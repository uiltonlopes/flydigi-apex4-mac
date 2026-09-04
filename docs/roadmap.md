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
- ✅ Keyboard / mouse mapping (2026-09-04): Special buttons → key / left or right click / wheel, sticks → keyboard (4 or 8 directions) or mouse, gyro → mouse. App-side engine posting CGEvents (Accessibility permission), mappings stored per controller and slot on the Mac; buttons need DInput because the firmware hides keyboard-flagged keys from the Xbox report. Verified on hardware: key, clicks, stick → mouse, and the gyro axes (yaw → X, pitch → Y; the pad only streams motion while the profile's gyro is on).
- ✅ Firmware update from the app: Settings › Firmware Update runs the whole sequence (download + validate, switch to DInput through the helper, OTA with progress, wait for the restart, back to XInput). Verified 2026-09-04: CLI 6.8.3.0 → 6.8.3.7, then the app re-flashed 6.8.3.7 end to end ([firmware-update.md](firmware-update.md) §6c).
- ✅ Settings: firmware update check with Flydigi's note, USB mode switch, language (en, pt-BR), GIPHY key, open at login, helper install/remove, device nickname.
- ✅ Release pipeline: Developer ID signing, notarization and stapling of app and DMG (`scripts/release.sh`).

## Needs a hardware test

- 🧪 **NS mode**: the profile is written to slots 4–7 exactly as Space Station does; nobody on the project owns a Switch, so it stays unverified until an owner reports.
- 🧪 Other Apex 4 editions (device ids 86, 87, 92, 93, 102, 103, 104): same protocol, artwork present, never connected here.

## Open

- ❌ **Share codes** compatible with Space Station: its codes carry the protobuf `ControllerMappingConfigBean` / `MacroItem`, not the device blob, so a bean ↔ blob converter is needed first (`MappingConfigParser` in SS4). Until then profiles and macros travel as `.fdgprofile` / `.fdgmacro` files.
- ❌ App self-update (Sparkle or a GitHub-releases check) once releases are public.
- ❌ Preferences: log file toggle, close-to-menu-bar vs quit.
- ❌ Helper hardening: audit-token peer check on macOS 14–15 (`XPCPeerRequirement` covers 26+), idle exit.
- ❌ Beyond Space Station: racing telemetry driving trigger resistance (Forza "Data Out", F1, Dirt, WRC); shareable community presets (LED themes, GIF packs, game profiles); Shortcuts / URL scheme automation.

## Not applicable on macOS

- 🚫 Space Station's game mods (DLL injection) and DS / PS5 mode (Windows kernel drivers). Per-app game profiles are our replacement.
- 🚫 Bluetooth configuration: Flydigi's BLE service only covers the BS1 cooler, not the Apex 4.
- 🚫 Screen upload over the 2.4 GHz receiver: the receiver never acks those packets. Cable only.
- 🚫 Joystick global settings, polling rate, vibration light effect, trigger vibration switch: hidden or unsupported for the Apex 4 in Space Station too.
