#!/bin/zsh
# Builds a Release "Space Station.app" (signed with the configured team) and packs it into a DMG + ZIP under dist/.
# Usage: scripts/release.sh 0.1.0
#
# Requirements: Xcode (DEVELOPER_DIR below), xcodegen, a signing identity for DEVELOPMENT_TEAM in
# SpaceStation/project.yml. Without a Developer ID + notarization, users must right-click → Open once.
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

echo "signature:"; codesign -dv --verbose=1 "$APP" 2>&1 | grep -E 'Identifier|Authority|TeamIdentifier' | head -4
codesign --verify --deep --strict "$APP" && echo "codesign verify OK"

mkdir -p "$DIST"; rm -f "$DIST"/SpaceStation-"$VERSION".{dmg,zip}
STAGE="$(mktemp -d)"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
cp "$ROOT/docs/install.md" "$STAGE/READ ME FIRST.md"
hdiutil create -quiet -volname "Space Station for Mac $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DIST/SpaceStation-$VERSION.dmg"
ditto -c -k --keepParent "$APP" "$DIST/SpaceStation-$VERSION.zip"
rm -rf "$STAGE"
shasum -a 256 "$DIST"/SpaceStation-"$VERSION".{dmg,zip} | tee "$DIST/SpaceStation-$VERSION.sha256"
echo "done → $DIST"
