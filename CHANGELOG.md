# Changelog

## Unreleased
- App renamed **Space Station for Mac** (repo `flydigi-space-station-mac`), Space Station's app icon.
- Lighting: mode list now matches Space Station's for the Apex 4 (Default, Steady, Breathing, Gradient, Off — no Flow/Feedback on this model), with per-mode colour limits (Steady 1, Gradient 2–5, Breathing up to 5). "Off" now blanks every LED unit like Space Station does (the pad kept playing the previous colours before). "Default" sends the factory loop and colours under mode 7 like Space Station.
- Welcome / device-center screen with the connected model's picture, connection and battery.
- Battery read through GameController when macOS provides it (no USB borrow), device-info byte otherwise.
- Screen editor: drag / pinch / scroll to frame the image in a 2:1 viewport, Fit / Fill, GIF trimming with
  filmstrip, frame interval, exact 160 × 80 preview; long GIFs are thinned evenly to 35 frames.
- Key capture in XInput borrows the pad for a few seconds so paddles and Fn work everywhere.
- Game profiles per app (Adaptive Trigger page): pick an app, a profile slot and trigger presets; applied when the app is in front, restored when it leaves. "Open at login" toggle.
- Stick / trigger calibration wizard (Joystick tab): timed, guided, with the controller's own "Calibrating" window.
- Credits, social links and Buy Me a Coffee in Settings → About, the welcome screen, the menu bar and the About panel.
- Firmware: automatic update check on connect, update badges (welcome screen, sidebar, Settings), Flydigi's
  note, how-to-update guidance, and a read-only dry run that downloads and validates the image (Telink CRC32)
  and finds the OTA interface. Flashing itself stays disabled.
- Settings reorganised (Controller → App → About), in-app language switch, pt-BR translation.
- App renamed internally (Space Station.app, `com.uiltonlopes.spacestation`, SpaceStationHelper).

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
