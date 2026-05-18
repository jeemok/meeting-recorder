#!/usr/bin/env bash
# Build a relocatable .app bundle from the SwiftPM executable.
#
# Usage:
#   ./build.sh                  # debug build → MeetingRecorder.app
#   ./build.sh release          # release build (optimized)
#   ./build.sh release sign     # release + ad-hoc codesign (for local Gatekeeper)
set -euo pipefail

CONFIG="${1:-debug}"
SIGN="${2:-}"
APP_NAME="MeetingRecorder"
BUNDLE="${APP_NAME}.app"
HERE="$(cd "$(dirname "$0")" && pwd)"

cd "${HERE}"

# Re-compile the app icon from the iconset if it's missing or stale.
if [[ -d Resources/AppIcon.iconset ]]; then
    if [[ ! -f Resources/AppIcon.icns ]] || \
       [[ -n "$(find Resources/AppIcon.iconset -newer Resources/AppIcon.icns 2>/dev/null)" ]]; then
        echo "→ iconutil -c icns Resources/AppIcon.iconset"
        iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
    fi
fi

echo "→ swift build --configuration ${CONFIG}"
swift build --configuration "${CONFIG}"

BIN_PATH="$(swift build --configuration "${CONFIG}" --show-bin-path)"
BIN="${BIN_PATH}/${APP_NAME}"

if [[ ! -x "${BIN}" ]]; then
    echo "✗ binary not found at ${BIN}" >&2
    exit 1
fi

echo "→ assembling ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "${BIN}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp Resources/diarize_sidecar.py "${BUNDLE}/Contents/Resources/diarize_sidecar.py"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Copy SwiftPM resource bundles (WhisperKit etc.) into the app's Resources.
for bundle in "${BIN_PATH}"/*.bundle; do
    [[ -e "${bundle}" ]] || continue
    cp -R "${bundle}" "${BUNDLE}/Contents/Resources/"
done

if [[ "${SIGN}" == "sign" ]]; then
    # Prefer a stable self-signed identity (see scripts/setup_signing.sh).
    # Without one, fall back to an ad-hoc signature — but the cdhash will
    # change every build, so macOS will re-prompt for mic / screen-recording
    # permission each launch.
    STABLE_IDENTITY="MeetingRecorder Local Signing"
    if security find-identity -p codesigning -v 2>/dev/null | grep -q "${STABLE_IDENTITY}"; then
        echo "→ codesign with '${STABLE_IDENTITY}'"
        codesign --force --deep --sign "${STABLE_IDENTITY}" "${BUNDLE}"
    else
        echo "→ ad-hoc codesign (run 'make trust' for stable permissions)"
        codesign --force --deep --sign - "${BUNDLE}"
    fi
fi

echo "✓ built ${HERE}/${BUNDLE}"
echo "  run: open ${BUNDLE}"
