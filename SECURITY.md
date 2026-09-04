# Security

The app talks to the controller over USB HID and, in XInput mode, through a privileged helper (a launchd
daemon registered with `SMAppService`). The helper only executes the fixed set of controller commands in
`FlydigiKit/Sources/FlydigiHelperProtocol/HelperProtocol.swift`; it never runs arbitrary code or touches files.
The app reaches three hosts: Flydigi's API (animation library, game presets, firmware notices, profile share
codes), GIPHY (search, only when you use it) and GitHub (release check). No account, no telemetry.

If you find a vulnerability — in the helper's XPC surface, the firmware flasher, the keyboard/mouse engine or
the `spacestation://` URL handler — please **do not open a public issue**. Email the maintainer via the address
on <https://github.com/uiltonlopes> or use GitHub's private vulnerability reporting on this repository. You
will get an answer within a week, and credit in the release notes if you want it.
