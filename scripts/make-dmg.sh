#!/usr/bin/env zsh
# Builds a Release InkBridge.app and packs it into a compressed DMG ready
# to upload to GitHub Releases. Reads the version from project.yml so a
# version bump there is the single source of truth.
#
# Run from the inkflow-app/ root:
#   scripts/make-dmg.sh
#
# Output:
#   build/InkBridge-<version>.dmg

set -euo pipefail

APP_NAME="InkBridge"
BUILD_DIR="build"
STAGE_DIR="${BUILD_DIR}/dmg-stage"

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
if [[ -z "${VERSION}" ]]; then
    echo "could not read MARKETING_VERSION from project.yml" >&2
    exit 1
fi

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

echo "==> Building ${APP_NAME} ${VERSION} (Release)"
xcodebuild \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    build \
    | tail -5

echo "==> Staging .app + /Applications symlink"
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"
cp -R "${APP_PATH}" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"

echo "==> Packing DMG"
rm -f "${DMG_PATH}"
hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "${STAGE_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" \
    | tail -3

rm -rf "${STAGE_DIR}"

echo
echo "Created ${DMG_PATH}"
ls -lh "${DMG_PATH}"
