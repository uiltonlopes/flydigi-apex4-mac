#!/bin/zsh
# Captures the Space Station window for the README: scripts/screenshot.sh <name> [spacestation://url]
# Needs the app running (Debug build is fine) and Screen Recording permission for the terminal.
set -e
NAME="${1:?usage: screenshot.sh <name> [url]}"; URL="$2"
OUT="$(dirname "$0")/../docs/screenshots"; mkdir -p "$OUT"
[ -n "$URL" ] && { open "$URL"; sleep 1.5; }
WID=$(swift "$(dirname "$0")/windowid.swift")
[ -n "$WID" ] || { echo "no Space Station window"; exit 1 }
screencapture -o -x -l "$WID" "$OUT/$NAME.png"
echo "$OUT/$NAME.png"
