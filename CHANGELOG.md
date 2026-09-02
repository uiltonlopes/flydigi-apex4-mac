# Changelog

## 0.1.0 — 2026-09-02 (pre-release)

First public build. Signed with a personal Apple Development certificate, not notarized: right-click →
Open on first launch (see `docs/install.md`).

**Controller support:** Flydigi Apex 4 (device id 84, firmware 6.8.3.x) over USB-C or the charging
base's 2.4 GHz receiver, in XInput (via privileged helper) and DInput (direct) modes.

**Features**
- Space Station 4-style interface: device card with battery, hero with the official wireframe and key
  layout, profile slots (rename / apply / revert), tabs Common · Button · Joystick · Gyro · Trigger · Macros.
- Lighting: mode, colours, brightness, cycle time, applied live and saved to flash.
- Buttons: click / turbo / macro per key, "press the button on the pad" capture (paddles included, in both modes).
- Joystick: curves (incl. custom two-point), dead zone, edge, live readout.
- Gyro: mapping, activation key/type, sensitivity, dead zone, use mode.
- Triggers: ForceAdapt modes with live preview, start/end, live readout.
- Macros: on-board macros with step editor, timeline and recording from the pad.
- Screen: GIF/PNG/JPEG upload (160×80, ≤35 frames) and Flydigi's official animation library.
- Adaptive Trigger: Flydigi's per-game preset list (read-only for now).
- Settings: helper install/remove, USB mode switch, firmware availability check.
- Live input: every key lights on the hero; in DInput the raw report is decoded (paddles, Fn, Home).

**Not yet**
- Firmware flashing, keyboard/mouse mapping, automatic per-game trigger switching, stick calibration wizard.
- Screen upload over the 2.4 GHz receiver (the receiver does not forward those commands).

**Known limits**
- In XInput mode Apple's driver hides paddles and Fn; the app borrows the pad for a few seconds when you
  ask it to capture a key.
