# Releasing

## One-time setup (Developer ID + notarization)

> Status 2026-09-02: the Developer Program is active and the **Developer ID Application** certificate exists
> (`Developer ID Application: UILTON LOPES DE MOURA (A2NY8257QF)`). The paid team kept the same Team ID as
> the old Personal Team, so `DEVELOPMENT_TEAM` did not change. Remaining: store the notary credentials
> (step 2) — after that `scripts/release.sh` notarizes and staples.

1. **Certificate.** Xcode → Settings → Accounts → select the team → *Manage Certificates…* → **+** →
   **Developer ID Application**. (Or create it at developer.apple.com → Certificates.) Check with
   `security find-identity -v -p codesigning`; you should see `Developer ID Application: <name> (<TEAMID>)`.
2. **Notary credentials.** Create an app-specific password at appleid.apple.com (Sign-In and Security →
   App-Specific Passwords), then store it once:
   ```bash
   xcrun notarytool store-credentials AC_NOTARY --apple-id <apple id email> --team-id <TEAMID> --password <app-specific password>
   ```
3. If the paid team has a *different* Team ID from the old Personal Team, update `DEVELOPMENT_TEAM` in
   `SpaceStation/project.yml`, then reinstall the helper once (the launchd constraint is per team).

## Every release

```bash
SIGN_IDENTITY="Developer ID Application: <name> (<TEAMID>)" NOTARY_PROFILE=AC_NOTARY scripts/release.sh 0.2.0
git tag -a v0.2.0 -m "Space Station for Mac 0.2.0" && git push origin v0.2.0
gh release create v0.2.0 dist/SpaceStation-0.2.0.dmg dist/SpaceStation-0.2.0.zip dist/SpaceStation-0.2.0.sha256 --title "0.2.0" --notes-file <(sed -n '/^## 0.2.0/,/^## /p' CHANGELOG.md | sed '$d')
```

Notarized builds open without the right-click dance; `docs/install.md` can drop that step once the first
notarized release is out.

## What Developer ID does not change

- The privileged helper still needs the user's one-time approval in *Login Items & Extensions*.
- DriverKit (a driver of our own for paddles in XInput) needs a separate entitlement request to Apple.
