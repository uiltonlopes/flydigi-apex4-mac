# Changelog

## Unreleased
- Profiles: local library ("Saved profiles…" in the profile menu) — save the current profile, load into the editor, rename, duplicate, reorder, delete, export/import as `.fdgprofile` (the raw 790-byte blob). SS4 share codes are not interoperable yet (they carry the protobuf bean, see docs/ss4-gap-analysis.md).
- Screen: "Factory animations" tab with the animation each Apex 4 edition ships with (yours is marked).
- Parity batch from the gap analysis: GIF frame interval is now really sent to the pad (start packet period); Settings › Controller gained Controller Sleep Time (1 min…3 h / never), Fast Swap Config (SELECT + A/B/X/Y) and the Turbo hardware shortcut switch; profile menu "Restore default configuration…"; Screen "Restore default animation"; device nickname (right-click the card); second gyro activation key.
- Sticks: sensitivity curve drawn like Space Station (280 × 280 grid, 0–100 axes, dead-zone and edge bands, 4-point curve with draggable nodes), always visible, with SS4's Default / Instant / Delay / Custom presets and a live dot for the current deflection.
- Triggers: Vibration (grip-sync) mode now really engages in the live preview (written through the profile, as Space Station does); the vibration test and the grip vibration test use the Xbox rumble packet games send, which the triggers follow.
- Triggers: per-mode defaults are now the Apex 4's own presets, read back from the pad after picking each mode in its screen menu (Race = light damping over the whole travel, Recoil, Sniper, Trigger lock levels 1–3, Vibration). "Controller preset" button restores them.
- Triggers: ForceAdapt modes now match Space Station for the Apex 4 — General, Racing, Recoil, Sniper, Trigger lock, Vibration (SS4's own labels and tooltips) — with SS4's parameters and ranges (0–255 raw, not 1–10), the vibration mode sent as the "sync with grip" command, and the same layout in the profile blob. Game-profile presets use the same editor.
- Receiver (charging dock): "waiting for controller" state while the pad is off, automatic reconnection when it comes back or when the receiver re-enumerates, battery read correctly over the receiver, no stale errors when it is unplugged.
- Welcome screen: Space Station's own "add device" silhouette when nothing is connected; special-edition card artwork (EVA-01, Assassin's Creed, Black Myth Wukong, Genshin, Honkai Star Rail).
- Sidebar: device card without the dropdown (refresh icon, short firmware-update button, mode switch on the Mode row), title on its own line.
- Screen: GIPHY search next to Flydigi's library (shared beta key, or your own in Settings) and an "On the controller" card showing the last animation sent from this Mac, or the factory animation for the connected variant (the pad cannot be read back).
- App renamed **Space Station for Mac** (repo `flydigi-space-station-mac`), Space Station's app icon.
- Fix: the Screen editor crashed when a shorter GIF/image replaced a longer one (filmstrip indexed stale frames).
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
