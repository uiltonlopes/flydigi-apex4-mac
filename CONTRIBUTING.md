# Contributing

Thanks for helping. Space Station for Mac is a from-scratch, MIT-licensed reimplementation of what Flydigi
Space Station does for the Apex 4, and the maintainer owns exactly one controller — so testing on other
firmware versions, editions and setups is the most valuable contribution there is.

## Ground rules

- **No Flydigi code or assets in pull requests.** Everything here is written from knowledge of the wire
  protocol. Do not commit their binaries, decompiled sources, images or copy. Document *what the bytes mean*.
  The artwork already in `SpaceStation/App/Resources/Flydigi/` is the one exception, listed in its NOTICE.md.
- **Never leave a controller worse than you found it.** Anything that writes to the pad must be verified on
  hardware first; dump the profiles before (`apex4 config dump ./backup`) and say in the PR what you tested on
  (model, firmware, USB mode, cable or receiver).
- Protocol claims go in `docs/protocol.md` and are either verified on hardware or marked *(unverified)*.
- Keep the app in English in code and UI strings; add the pt-BR translation in `Localizable.xcstrings`.

## Setting up

```bash
brew install xcodegen
cd FlydigiKit && swift build && swift test        # package + 40 tests (tests need Xcode, not just the CLT)
cd ../SpaceStation && xcodegen generate
xcodebuild -project SpaceStation.xcodeproj -scheme SpaceStation -configuration Debug -derivedDataPath build -destination 'platform=macOS' build
```

The privileged helper only registers when app and helper are signed by the same team: put your Apple ID in
Xcode (a free account is enough) and set `DEVELOPMENT_TEAM` in `SpaceStation/project.yml` locally — don't commit
that change. Without the helper the app still works fully in DInput mode.

Layout: `FlydigiKit/` (protocol, transports, models, `apex4` CLI, tests), `SpaceStation/App` (SwiftUI),
`SpaceStation/Helper` (launchd daemon), `docs/` (start with `architecture.md` and `protocol.md`).

## Pull requests

1. Open an issue first for anything bigger than a fix, so we agree on the approach.
2. Fork, branch from `main`, keep the PR focused. `swift test` must pass; CI runs it and builds the app.
3. Describe what changed, why, and how you tested it on hardware. Screenshots for UI changes.
4. Update `CHANGELOG.md` (Unreleased section) and the relevant doc in `docs/`.

Commit messages in English or Portuguese are both fine. Reviews usually happen within a few days.

## Adding another Flydigi controller

See `docs/adding-a-controller.md`. Same-generation pads (Apex 3, Vader 3) are a few evenings of work;
the new-protocol ones (Apex 5, Vader 4 Pro/5) are a project.

## Reporting bugs

Use the bug template. Attach the log from **Settings › Log › Export log…** and say which USB mode you were in.
Security issues: see `SECURITY.md`.
