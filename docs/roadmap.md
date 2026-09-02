# Roadmap

Feature parity with Flydigi Space Station 3.4.4.3 (Windows), then beyond. Status legend:
✅ proven on hardware · 🔬 protocol known, not implemented · ❓ needs reverse-engineering · 🚫 not applicable on macOS

## Milestone 0 — foundations
- [x] `FlydigiKit` package: packet framing (XInput/DInput), CRC, device info, config/LED blob read/write, save-to-flash, LVGL RGB565 encoder, screen upload state machine — with tests using the captured blobs.
- [x] Privileged helper: `Apex4Helper` (XPCListener, Codable protocol, IOUSBLib capture) registered via `SMAppService.daemon` — **validated on hardware from inside the launchd daemon** (device info/LED through the app). IOUSBHost capture was abandoned after a kernel panic.
- [~] Helper hardening: XPC peer must be signed by our team (`XPCPeerRequirement.isFromSameTeam()`, macOS 26+). TODO: audit-token check on macOS 14–15; idle exit.
- [x] `apex4` CLI: `info`, `led`, `screen`, `config dump/restore`, `mode` — info/LED/screen verified on hardware in both channels (`mode` untested).

## Milestone 1 — what the community asked for first
- [x] **LED** in the app: mode, colours, brightness, speed; persisted to flash. (Per-group colours: TODO.)
- [x] **Screen** in the app: GIF/PNG/JPEG → 160×80 (aspect-fill), ≤35 frames, quantised preview, per-frame progress. TODO: fit/fill/crop choice, real frame period in the start packet, online library.
- [x] Screen sleep time / status bar: read, set and restore verified (`A5 30 02..05`).
- [x] SwiftUI app `Apex4` — Status, Lighting and Screen verified on hardware through the helper (2026-09-01).
- [~] **Redesign per `docs/design.md`** (2026-09-01 evening): NavigationSplitView shell, stage, toolbar (slot picker · Refresh/Revert · Apply ⌘S), inspector, Settings scene, menu bar `.window`; **Profiles & Buttons** page v1 (hotspots over the stage + mapping table + button inspector: default / remap / turbo / macro). Awaiting visual review.

## Milestone 2 — controller configuration
- [~] Profiles: read/apply config slot verified (`A5 20`, `A5 50 05`); per-slot read/write + import/export pending.
- [~] Button mapping, macros, turbo: blob fields decoded; remap + macro write/read-back verified on hardware (`apex4 dev slot-write-test`, `dev macro-test`). UI pending.
- [~] Joystick: dead zone/curve decoded in the blob (write path proven); resolution/return rate/centre sensitivity/rebounce/round type commands known (`A5 50 0A/0B/0D…`), untested.
- [ ] **Calibration wizard** (`A5 14 01/02` start/stop, `A5 F6 06` stick test): only as a guided flow with live stick readout — starting/stopping blindly can leave sticks with a bogus range.
- [~] Triggers: ForceAdapt live command implemented (`A5 30 06`, Race/Sniper/Normal sent); dead zones/curves decoded in blob. Calibration, jitter TBD.
- [~] Vibration motor test verified (`A5 12`); motion mapping decoded in the blob, UI pending.
- [ ] 🔬 Live input viewer (GameController framework) for testing.

## Inputs from the Space Station 4 analysis (see `docs/spacestation4-analysis.md`)
- [~] Online GIF library: `FlydigiAPI.screenPictures()` + `apex4 api gifs` (38 items, verified live) — app UI pending.
- [~] Per-game trigger presets: `FlydigiAPI.gamePresets()` + `apex4 api games` (94 games, verified live) — feed Milestone 3.
- [x] Config blob (790 B) decoded/encoded in `GamepadConfig` (keys, sticks, triggers, ForceAdapt, motion, vibration, macros, title) with byte-exact round-trip; `apex4 config show`.
- [~] Firmware availability notice: `FlydigiAPI.firmwareUpdates()` + `apex4 api firmware` (6.8.3.7 offered, verified live) — app UI pending. Flashing stays out of scope.
- [x] Re-tested the DInput details flagged by the SS4 analysis (see `protocol.md` §3): keep `EA`/`E7`; acks are 1-based; DInput commands need 12-byte padding.

## Milestone 3 — beyond Space Station
- [ ] Per-game trigger/vibration profiles: detect the frontmost app (`NSWorkspace`) and apply the profile automatically (Space Station's `GameTriggerModService`, Windows-only today).
- [ ] Shareable community presets (LED themes, GIF packs, game profiles).
- [ ] Shortcuts / URL scheme / CLI automation.

## Later / research
- [x] 2.4 GHz dongle: LED/config work over the base's receiver (same XInput protocol). ❌ Screen upload gets no ack wirelessly — cable only.
- [ ] ❓ Firmware updates (MCU, dongle, trigger board, LCD via ESP32 bootloader). Highest risk; last.
- [ ] Keyboard/mouse mapping **the macOS way** (Milestone 3): the firmware only flags a key as `0xFE`; Flydigi's Windows driver does the translation. On macOS the app can read the pad via GameController and post `CGEvent`s (needs Accessibility permission, app running) — no kernel driver.
- [ ] 🚫 DualSense/DS-mode emulation — Windows kernel driver; a macOS equivalent would need a virtual HID driver (DriverKit). Out of scope.
- [ ] 🚫 Bluetooth configuration — Flydigi's BLE service only covers the BS1 cooler, not the Apex 4.
