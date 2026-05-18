#!/usr/bin/env bash
# Reinstall MeetingRecorder.app into /Applications.
#
# Steps:
#   1. Quit any running MeetingRecorder.
#   2. Remove /Applications/MeetingRecorder.app if present.
#   3. Build release-signed.
#   4. Copy mac/MeetingRecorder.app → /Applications/.
#   5. Launch it.
#
# Does NOT touch ~/Library/Application Support/MeetingRecorder
# (recordings + config) or TCC permissions.
set -euo pipefail

APP_NAME="MeetingRecorder"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${HERE}/${APP_NAME}.app"
DST="/Applications/${APP_NAME}.app"

cd "${HERE}"

echo "→ quitting ${APP_NAME} if running"
osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
# Fallback for the menubar/LSUIElement case where AppleScript can't find it.
pkill -x "${APP_NAME}" 2>/dev/null || true
# Give the process a moment to release file handles.
sleep 1

if [[ -d "${DST}" ]]; then
    echo "→ removing ${DST}"
    rm -rf "${DST}"
fi

./build.sh release sign

if [[ ! -d "${SRC}" ]]; then
    echo "✗ build did not produce ${SRC}" >&2
    exit 1
fi

echo "→ copying ${SRC} → ${DST}"
cp -R "${SRC}" "${DST}"

echo "→ open ${DST}"
open "${DST}"

echo "✓ reinstalled ${DST}"
