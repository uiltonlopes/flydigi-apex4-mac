# Installing Space Station for Mac

**Requirements:** macOS 15 or newer (Liquid Glass details on macOS 26), a Flydigi Apex 4 connected
over USB-C or through its charging base (2.4 GHz receiver).

## 1. Install the app

1. Open the `.dmg` and drag **Space Station.app** to Applications.
2. First launch: macOS will say the app is from an unidentified developer, because pre-release builds
   are signed with a personal certificate and not notarized. **Right-click Space Station.app → Open → Open**
   (once). If the button is missing, run in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Space Station.app
   ```

## 2. Install the helper (needed in XInput mode)

By default the controller is in **XInput** mode and Apple's own Xbox driver owns it. To talk to it the
app uses a small privileged helper that borrows the USB interface only while a command runs.

1. Open **Settings** (bottom of the sidebar) → **Install helper**.
2. macOS opens *Login Items & Extensions*; allow **SpaceStationHelper** and enter your password once.
3. Back in the app press the refresh icon. The sidebar should show your controller, firmware and battery.

Without the helper the app still works fully in **DInput** mode (switch with the menu on the device
card, or hold the controller's mode combination). The LCD upload always needs XInput + the cable.

## 3. Modes at a glance

| | XInput (default) | DInput |
|---|---|---|
| Games | see an Xbox controller | see a generic gamepad |
| Configuration | via helper | direct, no helper |
| Screen (GIF) upload | yes, cable only | no |
| Live view of paddles / Fn | only while capturing a key | always |

## Uninstall

Delete `Space Station.app`. To remove the helper first: Settings → **Remove helper**, or in Terminal
`sudo launchctl bootout system/com.uiltonlopes.spacestation.helper`.

## Safety

Everything the app writes (lighting, profiles, macros, screen) goes to the same flash areas Space
Station writes, using the same commands, verified on real hardware. Firmware flashing is deliberately
not implemented. If the screen ever gets stuck mid-upload, unplug and re-plug the controller.

## Support

Questions and bugs: open an issue on GitHub. If the app is useful to you, you can
[buy the author a coffee](https://buymeacoffee.com/uiltonlopes).
