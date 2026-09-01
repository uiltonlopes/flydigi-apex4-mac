# Architecture

Goal: a native macOS app that gives Flydigi Apex 4 owners everything Flydigi Space Station does
on Windows — and more — written from scratch, open source (MIT), using what Apple ships today.

## Stack (decided 2026-09-01)

| Layer | Choice | Why |
|---|---|---|
| Language | **Swift 6.3**, strict concurrency | Native, modern, what the toolchain on macOS 26 ships. |
| UI | **SwiftUI** (macOS 15 minimum, Liquid Glass on 26) — menu-bar extra + main window | Native look, `MenuBarExtra`, `Observation`, Settings scenes. |
| Live input | **GameController** framework | Works in both modes (Apple's Xbox dext in XInput; HID gamepad in DInput) — button test / mapping UI. |
| Protocol core | Swift package **`FlydigiKit`** (no UI, no I/O side effects): packet builders/parsers, config & LED blobs, LVGL encoder, upload state machine | Testable with **Swift Testing**; reusable by CLI, app and helper. |
| Transports | `IOHIDManager` (DInput, unprivileged) · **IOUSBLib** user-client API in `IOKit.usb` (XInput, privileged; libusb-style `USBDeviceReEnumerate` capture) | Both are Apple frameworks; no third-party USB stack. IOUSBHost capture was tried first and panicked the kernel (see risks). |
| Privileged helper | **launchd daemon registered with `SMAppService.daemon`**, talking to the app over **XPC** (`XPCListener`/`XPCSession`, Swift-native, macOS 14+; peer requirements on 26) | Screen upload needs the Xbox interface captured from Apple's driver, which requires root. One approval at install time, no password per action. |
| CLI | `apex4` (swift-argument-parser) on top of `FlydigiKit` | Power users, scripting, CI of the protocol. |
| Images | ImageIO / CoreGraphics for GIF decoding & resizing | No ImageMagick. |
| Packaging | Xcode project, Developer ID signed + notarized `.dmg`; Homebrew cask later | Outside the Mac App Store (sandboxing would block USB capture). |

## Processes

```
┌──────────────────────────┐  XPC (Codable)   ┌───────────────────────────────┐
│ Apex4.app (SwiftUI)      │◄────────────────►│ com.flydigi-mac.helper (root) │
│  • menu bar + window     │                  │  • IOUSBLib capture 045e:028e  │
│  • DInput HID directly   │                  │  • screen upload, XInput cfg   │
│  • GameController live   │                  │  • mode switch                 │
└──────────────────────────┘                  └───────────────────────────────┘
            │                                               │
            └──────────── FlydigiKit (shared package) ──────┘
```

- Anything that works in **DInput** (device info, config, LED, mapping, triggers…) runs **inside the
  app, unprivileged**, via `IOHIDManager` on interface 2.
- Anything that needs **XInput** (screen upload; LED/config while the pad is in XInput) goes through
  the **helper**.
- The app can switch modes by software (`05 ED` / `A5 17`) so the user never touches the hardware
  switch; the UI hides the mode entirely.

## Known risks (validate first — Milestone 0)

1. **USB capture from a launchd daemon.** Apple Developer Forums report that on macOS 15.3+
   `IOUSBHostInterface(… .deviceCapture)` can fail from a LaunchDaemon while it works from a root
   Terminal ([thread 774497](https://developer.apple.com/forums/thread/774497), FB16524420), and that
   `SMAppService` daemons hit TCC differences vs. `SMJobBless`
   ([thread 795686](https://developer.apple.com/forums/thread/795686)). Our libusb PoC (which uses
   IOUSBHost capture under the hood) **worked as root from a terminal on macOS 26.6**. The first
   engineering task is a minimal daemon that captures the pad and reads device info.
   **Update 2026-09-01:** the first IOUSBHost-based capture from the CLI (`sudo apex4 info`) read the
   device info successfully and the Mac **kernel-panicked seconds later** (`Kernel data abort`,
   `far 0x30`, panic report cites IOUSBHostInterface / XboxGamepad dext). Sequence used: device
   capture → `configure(1, matchInterfaces: false)` → interface open → interrupt IO → destroy.
   The Python prototype (libusb → legacy IOUSBLib `USBDeviceReEnumerate` with the capture mask,
   then `USBInterfaceOpen`) ran the same protocol dozens of times without a panic. Next attempt will
   mirror libusb's mechanism (IOUSBLib via IOKit, still an Apple framework) and must be run only with
   the user's consent, with unsaved work closed.
   **Update 2026-09-01 (later):** the IOUSBLib rewrite (libusb-style capture) works end to end from
   the CLI as root — device info, LED apply + save, single-frame screen upload in 4.5 s — and Apple's
   driver re-attaches cleanly on release. **Validated 2026-09-01 (evening): the same IOUSBLib code runs inside the `SMAppService` launchd daemon** (root) and serves the app over XPC — device info and LED read through the daemon, no re-enumeration loops, no panic.
   Fallbacks, in order: (a) helper installed as a classic LaunchDaemon by a signed `.pkg`;
   (b) DriverKit USB dext — clean but needs Apple to grant
   `com.apple.developer.driverkit.transport.usb` for VID `0x045E` (Microsoft's), which is unlikely,
   and would also require re-exposing the gamepad as HID.
2. **Mode switching** commands are read from Flydigi's code but not yet exercised.
3. **Firmware updates**: Flydigi ships `esptool` for the LCD (ESP32) and vendor loaders for the
   MCU. Out of scope until the rest is solid; must never brick a pad.

## Development gotchas

- **Helper killed at launch with `Launch Constraint Violation` / launchd `last exit code = 78 (EX_CONFIG)`.**
  launchd caches a spawn constraint derived from the daemon's *designated requirement* at first
  registration. Re-signing the helper (e.g. ad-hoc → team, or a changed signing identifier) makes every
  later launch fail, even after `SMAppService.unregister()`/`register()`
  ([forum 795022](https://developer.apple.com/forums/thread/795022),
  [forum 799933](https://developer.apple.com/forums/thread/799933)). Fix: `sudo launchctl bootout
  system/com.uiltonlopes.apex4.helper`, then re-register from the app; if that is not enough,
  `sudo sfltool resetbtm` and reboot (resets *all* login-item registrations on the Mac). Keep the
  helper's signing identifier and team stable across releases for the same reason.
- Rebuilding the helper with the **same** identity is fine: the daemon notices its executable changed
  and exits when idle; launchd relaunches it on the next XPC connection.

## Repository layout (target)

```
FlydigiKit/        Swift package: protocol, blobs, LVGL, state machines, tests
Apex4/             Xcode project: app + helper targets
apex4-cli/         command-line tool
docs/              protocol.md · architecture.md · roadmap.md
research/python/   the prototypes that proved the protocol (reference only)
```
