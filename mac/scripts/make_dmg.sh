#!/usr/bin/env bash
# Package MeetingRecorder.app into a distributable .dmg.
#
# Usage:
#   ./make_dmg.sh                # build release-signed, then package
#   ./make_dmg.sh --skip-build   # reuse an existing MeetingRecorder.app
#
# Output: mac/MeetingRecorder-<version>.dmg
set -euo pipefail

SKIP_BUILD=0
if [[ "${1:-}" == "--skip-build" ]]; then
    SKIP_BUILD=1
fi

APP_NAME="MeetingRecorder"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
APP="${HERE}/${APP_NAME}.app"

cd "${HERE}"

if [[ ${SKIP_BUILD} -eq 0 ]]; then
    ./build.sh release sign
fi

if [[ ! -d "${APP}" ]]; then
    echo "✗ ${APP} not found — run './build.sh release sign' first" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "${APP}/Contents/Info.plist" 2>/dev/null || echo "dev")"
DMG="${HERE}/${APP_NAME}-${VERSION}.dmg"
VOLNAME="${APP_NAME} ${VERSION}"

STAGE="$(mktemp -d -t meetingrecorder-dmg)"
trap 'rm -rf "${STAGE}"' EXIT

echo "→ staging ${STAGE}"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

echo "→ hdiutil create ${DMG}"
rm -f "${DMG}"
hdiutil create \
    -volname "${VOLNAME}" \
    -srcfolder "${STAGE}" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "${DMG}" >/dev/null

echo "✓ ${DMG}"
echo "  size: $(du -h "${DMG}" | cut -f1)"
