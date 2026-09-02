# Space Station for Mac

Native, open-source macOS companion for **Flydigi controllers**: LEDs, LCD animations, profiles,
macros, triggers and more — what Flydigi Space Station does on Windows, on your Mac. Unofficial;
not affiliated with Flydigi. First supported controller: **Apex 4** (others: see *Supported hardware*).

> Status: **usable, pre-release.** The USB protocol is reverse-engineered and verified on real
> hardware, and the app covers everything Space Station 4 offers for the Apex 4 except firmware
> flashing and keyboard/mouse mapping. See [`docs/protocol.md`](docs/protocol.md) and
> [`docs/roadmap.md`](docs/roadmap.md).

## What the app does

Laid out like Space Station 4 so owners feel at home, built with SwiftUI:

- **Common** — lighting (mode, colours, brightness, cycle time; applied live) and grip vibration.
- **Button** — click / turbo / macro / special per key, with "press the button on the pad" capture.
- **Joystick** — curve (incl. custom two-point curve), dead zone, edge, live readout.
- **Gyro** — map motion to a stick, activation key, sensitivity, dead zone.
- **Trigger** — ForceAdapt modes (race, sniper, recoil, lock, vibration) with live preview, start/end.
- **Macros** — on-board macros with a step editor, timeline and recording from the pad.
- **Screen** — upload GIF/PNG/JPEG or pick from Flydigi's official library (cable, XInput).
- **Adaptive Trigger** — Flydigi's per-game preset list; **Settings** — helper, USB mode, firmware notice.
- 4 on-board profile slots with rename, apply and revert; battery, link and mode in the sidebar.

Live input works in both USB modes; in DInput the app also reads the raw report, so paddles
M1–M4, Fn and Home light up too. Controller artwork is Flydigi's (see
[`SpaceStation/App/Resources/Flydigi/NOTICE.md`](SpaceStation/App/Resources/Flydigi/NOTICE.md)); all code is ours.

## Why

Flydigi only ships configuration software for Windows. The controller works fine as a gamepad on
macOS, but you cannot change lighting, upload GIFs to the screen, or tune triggers and sticks.
Running the Windows app in a VM does not work either: Apple's own Xbox controller driver claims
the device before the VM can.

## How it works (short version)

- In **DInput** mode the pad exposes a vendor HID interface that macOS leaves alone → the app talks
  to it directly, no privileges needed (LEDs, config, profiles).
- In **XInput** mode Apple's driver owns the device; the LCD upload only works in this mode, so a
  small privileged helper (installed once, `SMAppService`) captures the interface for the app.
- Image format for the screen is LVGL v8 / RGB565 big-endian, 160×80, up to 35 frames.

Details: [`docs/architecture.md`](docs/architecture.md) · [`docs/roadmap.md`](docs/roadmap.md).

## Repository

```
SpaceStation/     the macOS app (SwiftUI) and the privileged helper — `SpaceStation/project.yml` is the xcodegen spec
FlydigiKit/       Swift package: protocol, transports, config/LED/screen models, `apex4` CLI, tests
docs/             protocol, architecture, design references, roadmap, install guide, adding a controller
scripts/          release packaging
tools/            ss4-harness: runs Space Station's own UI in a browser for design comparison (our mock only)
```

## Building the app

```bash
brew install xcodegen
cd SpaceStation && xcodegen generate
xcodebuild -project SpaceStation.xcodeproj -scheme SpaceStation -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Space Station.app
```
Local builds are ad-hoc signed. To register the privileged helper (needed for screen uploads while the
pad is in XInput mode) the app and helper must be signed with a team: add your Apple ID in Xcode
(a free account is enough) and set `DEVELOPMENT_TEAM` in `SpaceStation/project.yml`.

## Building the CLI

```bash
cd FlydigiKit && swift build
.build/debug/apex4 info                 # DInput mode: no privileges needed
.build/debug/apex4 led steady ff0000    # saved to flash
sudo .build/debug/apex4 screen my.gif   # XInput mode: needs root (screen upload)
swift test                              # needs Xcode (Swift Testing is not in the Command Line Tools)
```

## Supported hardware

| Controller | Device id | Firmware tested | Status |
|---|---|---|---|
| Flydigi Apex 4 (`k2`) | 84 | 6.8.3.0 (2026-09) | supported — LED, screen, profiles, macros, ForceAdapt, settings |
| Apex 4 EVA / STN / AC / GS / SRS / HSH | 86, 87, 92, 93, 102, 103, 104 | — | same family, untested |
| Apex 3, Vader 3 / 3 Pro, older | see catalogue | — | classic protocol, unsupported (help wanted) |
| Apex 5 / 6, Vader 4 Pro, Vader 5 | 128+ | — | new protocol (VID 0x37D7), unsupported |

Want yours added? Read [`docs/adding-a-controller.md`](docs/adding-a-controller.md).

## Contributing

Issues and PRs welcome — especially from Apex 4 owners who can test on different firmware
versions, the 2.4 GHz dongle, and other k2-family variants (EVA, STN…). Please **do not** commit
any Flydigi binaries or decompiled sources; this project is written from scratch under the MIT
license, using only knowledge of the wire protocol.

## Credits

Ported to macOS by **Uilton Lopes** — [github.com/uiltonlopes](https://github.com/uiltonlopes) ·
[linkedin.com/in/uiltonlopes](https://www.linkedin.com/in/uiltonlopes). Controller artwork and app icon
© Flydigi, used for interoperability (see the NOTICE next to them). Everything else MIT.

## Disclaimer

Not affiliated with Flydigi. Writing to the controller's flash/LCD is at your own risk; the
research scripts were tested on one unit (firmware 6.8.3.0).
