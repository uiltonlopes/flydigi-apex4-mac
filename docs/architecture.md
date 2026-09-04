# Architecture

Goal: a native macOS app that gives Flydigi Apex 4 owners everything Flydigi Space Station does
on Windows — and more — written from scratch, open source (MIT), using what Apple ships today.

## Stack (decided 2026-09-01)

| Layer | Choice | Why |
|---|---|---|
| Language | **Swift 6** language mode, strict concurrency (Xcode 26 toolchain) | Native, modern, what the toolchain on macOS 26 ships. |
| UI | **SwiftUI** (macOS 15 minimum) — menu-bar extra + main window, Space Station 4's dark layout drawn with native controls (`Theme.swift`) | Native look, `MenuBarExtra`, `Observation`. |
| Live input | **GameController** framework | Works in both modes (Apple's Xbox dext in XInput; HID gamepad in DInput) — button test / mapping UI. |
| Protocol core | Swift package **`FlydigiKit`** (no UI, no I/O side effects): packet builders/parsers, config & LED blobs, LVGL encoder, upload state machine | Testable with **Swift Testing**; reusable by CLI, app and helper. |
| Transports | `IOHIDManager` (DInput, unprivileged) · **IOUSBLib** user-client API in `IOKit.usb` (XInput, privileged; libusb-style `USBDeviceReEnumerate` capture) | Both are Apple frameworks; no third-party USB stack. IOUSBHost capture was tried first and panicked the kernel (see risks). |
| Privileged helper | **launchd daemon registered with `SMAppService.daemon`**, talking to the app over **XPC** (`XPCListener`/`XPCSession`, Swift-native, macOS 14+; peer requirements on 26) | Screen upload needs the Xbox interface captured from Apple's driver, which requires root. One approval at install time, no password per action. |
| CLI | `apex4` (swift-argument-parser) on top of `FlydigiKit` | Power users, scripting, CI of the protocol. |
| Images | ImageIO / CoreGraphics for GIF decoding & resizing | No ImageMagick. |
| Packaging | Xcode project, Developer ID signed + notarized `.dmg`; Homebrew cask later | Outside the Mac App Store (sandboxing would block USB capture). |

## Processes

```
┌────────────────────────────┐  XPC (Codable)   ┌──────────────────────────────────────┐
│ Space Station.app (SwiftUI)│◄────────────────►│ com.uiltonlopes.spacestation.helper  │
│  • menu bar + window       │                  │ (root, SMAppService daemon)          │
│  • DInput HID directly     │                  │  • IOUSBLib capture 045e:028e        │
│  • GameController live     │                  │  • screen upload, XInput cfg/LED     │
│  • keyboard/mouse engine   │                  │  • mode switch, firmware "enter OTA" │
└──────────────────────────┘                  └───────────────────────────────┘
            │                                               │
            └──────────── FlydigiKit (shared package) ──────┘
```

- Anything that works in **DInput** (device info, config, LED, mapping, triggers…) runs **inside the
  app, unprivileged**, via `IOHIDManager` on interface 2.
- Anything that needs **XInput** (screen upload; LED/config while the pad is in XInput) goes through
  the **helper**.
- The app can switch modes by software (`05 ED` / `A5 17`) so the user never touches the hardware
  switch; the Mode row on the device card and Settings › USB mode do it.

## Decisions validated on hardware

1. **USB capture in XInput.** Apple's Xbox driver owns the pad. The first attempt, IOUSBHost
   `deviceCapture` from the CLI, read the device info and then **kernel-panicked macOS 26.6** (2026-09-01,
   `Kernel data abort` citing IOUSBHostInterface / the XboxGamepad dext). The libusb mechanism — legacy
   IOUSBLib `USBDeviceReEnumerate` with the capture mask, then `USBInterfaceOpen` — runs the same protocol
   without incident, and **works inside the `SMAppService` launchd daemon** (root) over XPC. Apple Developer
   Forums threads [774497](https://developer.apple.com/forums/thread/774497) and
   [795686](https://developer.apple.com/forums/thread/795686) describe capture failing from LaunchDaemons on
   15.3+; not reproduced here. Fallbacks if it ever breaks: a classic LaunchDaemon installed by a signed `.pkg`,
   or a DriverKit dext (needs Apple to grant `com.apple.developer.driverkit.transport.usb` for Microsoft's
   VID `0x045E`, unlikely).
2. **Mode switching** (`05 ED` / `A5 17`) verified both ways; the firmware flow relies on it.
3. **Firmware** (main chip, Telink OTA over the DInput `0xFFEF` interface) implemented and run on hardware —
   see `firmware-update.md`. Screen and trigger-board chips are documented there, not implemented.

## Development gotchas

- **Helper killed at launch with `Launch Constraint Violation` / launchd `last exit code = 78 (EX_CONFIG)`.**
  launchd caches a spawn constraint derived from the daemon's *designated requirement* at first
  registration. Re-signing the helper (e.g. ad-hoc → team, or a changed signing identifier) makes every
  later launch fail, even after `SMAppService.unregister()`/`register()`
  ([forum 795022](https://developer.apple.com/forums/thread/795022),
  [forum 799933](https://developer.apple.com/forums/thread/799933)). Fix: `sudo launchctl bootout
  system/com.uiltonlopes.spacestation.helper`, then re-register from the app; if that is not enough,
  `sudo sfltool resetbtm` and reboot (resets *all* login-item registrations on the Mac). Keep the
  helper's signing identifier and team stable across releases for the same reason.
- Rebuilding the helper with the **same** identity is fine: the daemon notices its executable changed
  and exits when idle; launchd relaunches it on the next XPC connection.

## Repository layout

```
FlydigiKit/        Swift package: FlydigiKit (protocol, blobs, LVGL, models) · FlydigiTransport (HID, IOUSBLib,
                   sessions, Flydigi web API) · FlydigiHelperProtocol (XPC messages) · apex4 (CLI) · tests
SpaceStation/      xcodegen spec (project.yml), the SwiftUI app (App/) and the privileged helper (Helper/)
scripts/           release.sh — build, sign, notarize, staple, DMG
docs/              protocol · architecture · roadmap · firmware research · SS4 analysis · adding a controller · install · release
```
