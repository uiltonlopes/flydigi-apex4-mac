# Roadmap

Feature parity with Flydigi Space Station 3.4.4.3 (Windows), then beyond. Status legend:
✅ proven on hardware · 🔬 protocol known, not implemented · ❓ needs reverse-engineering · 🚫 not applicable on macOS

## Milestone 0 — foundations
- [x] `FlydigiKit` package: packet framing (XInput/DInput), CRC, device info, config/LED blob read/write, save-to-flash, LVGL RGB565 encoder, screen upload state machine — with tests using the captured blobs.
- [x] Privileged helper: `SpaceStationHelper` (XPCListener, Codable protocol, IOUSBLib capture) registered via `SMAppService.daemon` — **validated on hardware from inside the launchd daemon** (device info/LED through the app). IOUSBHost capture was abandoned after a kernel panic.
- [~] Helper hardening: XPC peer must be signed by our team (`XPCPeerRequirement.isFromSameTeam()`, macOS 26+). TODO: audit-token check on macOS 14–15; idle exit.
- [x] `apex4` CLI: `info`, `led`, `screen`, `config dump/restore`, `mode` — info/LED/screen verified on hardware in both channels (`mode` untested).

## Milestone 1 — what the community asked for first
- [x] **LED** in the app: mode, colours, brightness, speed; persisted to flash. (Per-group colours: TODO.)
- [x] **Screen** in the app: GIF/PNG/JPEG → 160×80, ≤35 frames (evenly thinned), quantised preview, per-frame progress, **editor** (pan/zoom/fit/fill, trim, interval), online library. TODO: send the chosen frame interval in the start packet.
- [x] Screen sleep time / status bar: read, set and restore verified (`A5 30 02..05`).
- [x] SwiftUI app `Apex4` — Status, Lighting and Screen verified on hardware through the helper (2026-09-01).
- [x] **Redesign in the Space Station 4 layout** (2026-09-01, validated by the owner): 248 pt sidebar with device card, battery and rail (Adaptive Trigger · Screen · Settings); hero with SS4's wireframe, key silhouettes and hotspot geometry; profile dropdown + Apply/Revert; tabs Common · Button · Joystick · Gyro · Trigger · Macros. Reference captured from the real renderer (`docs/design-ss4-reference.md`, `tools/ss4-harness/`).

## Milestone 2 — controller configuration
- [~] Profiles: read/apply config slot verified (`A5 20`, `A5 50 05`); per-slot read/write + import/export pending.
- [x] Button mapping, turbo, macros in the app: Click / Turbo / Macro / Special editor with "press the button on the pad" capture; Macros tab with step editor, timeline and recording from the pad. Remap + macro write/read-back verified on hardware.
- [~] Joystick tab: curve (Default/Quick/Slow/Custom with draggable points), dead zone, edge, live gauge. Resolution/return rate/centre sensitivity/rebounce/round type commands known (`A5 50 0A/0B/0D…`), untested.
- [ ] **Calibration wizard** (`A5 14 01/02` start/stop, `A5 F6 06` stick test): only as a guided flow with live stick readout — starting/stopping blindly can leave sticks with a bogus range.
- [x] Trigger tab: ForceAdapt modes with live preview and "keep in profile", start/end, live gauge (parameter layout partly inferred — see `Controls.swift`).
- [x] Common tab: lighting (debounced live apply) and grip vibration with motor test; Gyro tab: mapping, activation key/type, sensitivity, dead zone, use mode.
- [x] Live input: GameController framework in both modes, plus the **raw DInput status report** (paddles M1–M4, Fn, Home, sticks, triggers — `protocol.md` §9) so the hero lights every key and capture/recording see the paddles.

## Inputs from the Space Station 4 analysis (see `docs/spacestation4-analysis.md`)
- [x] Online GIF library in the Screen page ("Official selection": pick → preview → send).
- [~] Per-game trigger presets: `FlydigiAPI.gamePresets()` listed in the Adaptive Trigger page (94 games) — automatic switching is Milestone 3.
- [x] Config blob (790 B) decoded/encoded in `GamepadConfig` (keys, sticks, triggers, ForceAdapt, motion, vibration, macros, title) with byte-exact round-trip; `apex4 config show`.
- [x] Firmware availability notice in Settings ("Check Flydigi for updates"). Flashing stays out of scope.
- [x] Re-tested the DInput details flagged by the SS4 analysis (see `protocol.md` §3): keep `EA`/`E7`; acks are 1-based; DInput commands need 12-byte padding.

## Milestone 3 — beyond Space Station
- [ ] Per-game trigger/vibration profiles: detect the frontmost app (`NSWorkspace`) and apply the profile automatically (Space Station's `GameTriggerModService`, Windows-only today).
- [ ] Shareable community presets (LED themes, GIF packs, game profiles).
- [ ] Shortcuts / URL scheme / CLI automation.

## Later / research
- [x] 2.4 GHz dongle: LED/config work over the base's receiver (same XInput protocol); device info (model, firmware, battery) comes from the pad. ❌ Screen upload gets no ack wirelessly — cable only.
- [ ] Battery level in XInput/dongle refresh loop (currently read once per refresh; SS4 polls a heartbeat).
- [ ] ❓ Firmware updates (MCU, dongle, trigger board, LCD via ESP32 bootloader). Highest risk; last.
- [ ] Keyboard/mouse mapping **the macOS way** (Milestone 3): the firmware only flags a key as `0xFE`; Flydigi's Windows driver does the translation. On macOS the app can read the pad via GameController and post `CGEvent`s (needs Accessibility permission, app running) — no kernel driver.
- [ ] 🚫 DualSense/DS-mode emulation — Windows kernel driver; a macOS equivalent would need a virtual HID driver (DriverKit). Out of scope.
- [ ] 🚫 Bluetooth configuration — Flydigi's BLE service only covers the BS1 cooler, not the Apex 4.
