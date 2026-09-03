#!/bin/zsh
# Builds a Release "Space Station.app" (signed with the configured team) and packs it into a DMG + ZIP under dist/.
# Usage: scripts/release.sh 0.1.0
#
# Requirements: Xcode (DEVELOPER_DIR below), xcodegen, a signing identity for DEVELOPMENT_TEAM in
# SpaceStation/project.yml.
#
# Distribution signing (recommended, needs the paid developer account):
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=AC_NOTARY scripts/release.sh 0.2.0
# re-signs app + helper with the Developer ID certificate, notarizes with `notarytool` (credentials stored
# once via `xcrun notarytool store-credentials AC_NOTARY …`, see docs/release.md) and staples the ticket.
# Without those variables the build keeps the Apple Development signature and users must right-click → Open.
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DIST="$ROOT/dist"
BUILD="$ROOT/SpaceStation/build-release"
APP="$BUILD/Build/Products/Release/Space Station.app"

cd "$ROOT/SpaceStation"
xcodegen generate >/dev/null
xcodebuild -project SpaceStation.xcodeproj -scheme SpaceStation -configuration Release -derivedDataPath "$BUILD" \
  -destination 'platform=macOS' -allowProvisioningUpdates \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$(git -C "$ROOT" rev-list --count HEAD)" \
  build 2>&1 | grep -E 'error:|warning: .*(signing|entitle)|BUILD (SUCCEEDED|FAILED)' | grep -v ArgumentParser || true
[ -d "$APP" ] || { echo "build failed: $APP missing" >&2; exit 1; }

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "re-signing with: $SIGN_IDENTITY"
  codesign --force --options runtime --timestamp -s "$SIGN_IDENTITY" --identifier com.uiltonlopes.spacestation.helper "$APP/Contents/MacOS/SpaceStationHelper"
  codesign --force --options runtime --timestamp -s "$SIGN_IDENTITY" --entitlements "$ROOT/SpaceStation/App/SpaceStation.entitlements" "$APP"
fi
echo "signature:"; codesign -dv --verbose=1 "$APP" 2>&1 | grep -E 'Identifier|Authority|TeamIdentifier' | head -4
codesign --verify --deep --strict "$APP" && echo "codesign verify OK"

mkdir -p "$DIST"; rm -f "$DIST"/SpaceStation-"$VERSION".{dmg,zip}
notarize() { xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | grep -E "status:|id:" | tail -2; }

# 1. Notarize the app itself (as a zip) and staple the ticket onto the bundle, so the app launches clean
#    even when copied out of the DMG or downloaded as the zip.
ditto -c -k --keepParent "$APP" "$DIST/SpaceStation-$VERSION.zip"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "notarizing the app (a few minutes)…"; notarize "$DIST/SpaceStation-$VERSION.zip"
  xcrun stapler staple "$APP" | tail -1
  rm -f "$DIST/SpaceStation-$VERSION.zip"; ditto -c -k --keepParent "$APP" "$DIST/SpaceStation-$VERSION.zip"   # zip of the stapled app
fi

# 2. DMG from the stapled app, signed as well (Gatekeeper's "open" assessment wants a signature on the image).
STAGE="$(mktemp -d)"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
cp "$ROOT/docs/install.md" "$STAGE/READ ME FIRST.md"
hdiutil create -quiet -volname "Space Station for Mac $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DIST/SpaceStation-$VERSION.dmg"
rm -rf "$STAGE"
if [ -n "${SIGN_IDENTITY:-}" ]; then codesign --force --timestamp -s "$SIGN_IDENTITY" "$DIST/SpaceStation-$VERSION.dmg"; fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "notarizing the DMG…"; notarize "$DIST/SpaceStation-$VERSION.dmg"
  xcrun stapler staple "$DIST/SpaceStation-$VERSION.dmg" | tail -1
  echo "gatekeeper:"
  spctl -a -vv -t exec "$APP" 2>&1 | tail -2
  spctl -a -vv -t open --context context:primary-signature "$DIST/SpaceStation-$VERSION.dmg" 2>&1 | tail -2 || true
fi
shasum -a 256 "$DIST"/SpaceStation-"$VERSION".{dmg,zip} | tee "$DIST/SpaceStation-$VERSION.sha256"
echo "done → $DIST"
