# Roadmap

Feature parity with Flydigi Space Station 3.4.4.3 (Windows), then beyond. Status legend:
✅ proven on hardware · 🔬 protocol known, not implemented · ❓ needs reverse-engineering · 🚫 not applicable on macOS

## Milestone 0 — foundations
- [x] `FlydigiKit` package: packet framing (XInput/DInput), CRC, device info, config/LED blob read/write, save-to-flash, LVGL RGB565 encoder, screen upload state machine — with tests using the captured blobs.
- [ ] Privileged helper PoC: `SMAppService.daemon` + XPC + `IOUSBHost` capture of `045e:028e`; read device info. **Go/no-go for the architecture.**
- [x] `apex4` CLI: `info`, `led`, `screen`, `config dump/restore`, `mode` — info/LED/screen verified on hardware in both channels (`mode` untested).

## Milestone 1 — what the community asked for first
- [ ] ✅→app **LED**: mode, colours per group, brightness, speed; persist to flash.
- [ ] ✅→app **Screen**: upload GIF/PNG/JPEG (auto crop/resize to 160×80, ≤35 frames, preview of the quantised result), progress, library of animations.
- [ ] 🔬 Screen standby/sleep time, status bar on/off.
- [ ] Menu-bar app: battery %, connection (wired / 2.4 GHz), current profile.

## Milestone 2 — controller configuration
- [ ] 🔬 Profiles (config slots), switch active profile, import/export (`.fdg` compatible?).
- [ ] 🔬 Button mapping, macros, turbo.
- [ ] 🔬 Joystick: dead zone, curve, resolution, return rate, centre sensitivity, rebounce algorithm, round type; **calibration**.
- [ ] 🔬 Triggers: ForceAdapt modes, vibration, dead zones, jitter elimination; **calibration**.
- [ ] 🔬 Vibration motors test; gyro / motion mapping.
- [ ] 🔬 Live input viewer (GameController framework) for testing.

## Milestone 3 — beyond Space Station
- [ ] Per-game trigger/vibration profiles: detect the frontmost app (`NSWorkspace`) and apply the profile automatically (Space Station's `GameTriggerModService`, Windows-only today).
- [ ] Shareable community presets (LED themes, GIF packs, game profiles).
- [ ] Shortcuts / URL scheme / CLI automation.

## Later / research
- [x] 2.4 GHz dongle: LED/config work over the base's receiver (same XInput protocol). ❌ Screen upload gets no ack wirelessly — cable only.
- [ ] ❓ Firmware updates (MCU, dongle, trigger board, LCD via ESP32 bootloader). Highest risk; last.
- [ ] 🚫 DualSense/DS-mode emulation, keyboard-mouse mapping driver — Windows kernel drivers; a macOS
      equivalent would need a virtual HID driver (DriverKit). Out of scope for now.
- [ ] 🚫 Bluetooth configuration — Flydigi's BLE service only covers the BS1 cooler, not the Apex 4.
