#!/usr/bin/env zsh
# Builds a Release InkBridge.app (Developer ID signed, hardened runtime),
# notarizes and staples it, then packs it into a notarized + stapled DMG
# ready to upload to GitHub Releases. Reads the version from project.yml
# so a version bump there is the single source of truth.
#
# Run from the inkflow-app/ root:
#   scripts/make-dmg.sh
#
# Prerequisites (one-time setup):
#   - Developer ID Application certificate installed in login keychain
#   - notarytool keychain profile stored under ${NOTARY_PROFILE} (default
#     "inkbridge-notary"). Create with:
#         xcrun notarytool store-credentials "inkbridge-notary" \
#             --apple-id "<apple-id>" --team-id "S7GCDX6XVW"
#
# Output:
#   build/InkBridge-<version>.dmg

set -euo pipefail

APP_NAME="InkBridge"
BUILD_DIR="build"
STAGE_DIR="${BUILD_DIR}/dmg-stage"
NOTARY_PROFILE="${NOTARY_PROFILE:-inkbridge-notary}"

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
if [[ -z "${VERSION}" ]]; then
    echo "could not read MARKETING_VERSION from project.yml" >&2
    exit 1
fi

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
ZIP_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.zip"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

echo "==> Building ${APP_NAME} ${VERSION} (Release, Developer ID + hardened runtime)"
xcodebuild \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    build \
    | tail -5

echo "==> Verifying signature on .app"
codesign --verify --strict --verbose=2 "${APP_PATH}"
# Confirm hardened runtime + timestamp landed
codesign -dvv "${APP_PATH}" 2>&1 | grep -E "Authority|Timestamp|Runtime|flags" || true

echo "==> Zipping .app for notarization submission"
rm -f "${ZIP_PATH}"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "==> Submitting .app to notarytool (this can take a few minutes)"
APP_SUBMIT_LOG="$(xcrun notarytool submit "${ZIP_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait)"
echo "${APP_SUBMIT_LOG}"
APP_SUBMIT_ID="$(echo "${APP_SUBMIT_LOG}" | awk '/^  id:/ {print $2; exit}')"
if ! echo "${APP_SUBMIT_LOG}" | grep -q "status: Accepted"; then
    echo "Notarization failed for .app. Fetching log:" >&2
    xcrun notarytool log "${APP_SUBMIT_ID}" --keychain-profile "${NOTARY_PROFILE}" >&2 || true
    exit 1
fi
rm -f "${ZIP_PATH}"

echo "==> Stapling notarization ticket to .app"
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"

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

echo "==> Signing DMG"
codesign --sign "Developer ID Application" --timestamp "${DMG_PATH}"

echo "==> Submitting DMG to notarytool"
DMG_SUBMIT_LOG="$(xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait)"
echo "${DMG_SUBMIT_LOG}"
DMG_SUBMIT_ID="$(echo "${DMG_SUBMIT_LOG}" | awk '/^  id:/ {print $2; exit}')"
if ! echo "${DMG_SUBMIT_LOG}" | grep -q "status: Accepted"; then
    echo "Notarization failed for DMG. Fetching log:" >&2
    xcrun notarytool log "${DMG_SUBMIT_ID}" --keychain-profile "${NOTARY_PROFILE}" >&2 || true
    exit 1
fi

echo "==> Stapling notarization ticket to DMG"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"

echo
echo "Created ${DMG_PATH}"
ls -lh "${DMG_PATH}"
echo
echo "Gatekeeper check:"
spctl -a -t open --context context:primary-signature -vv "${DMG_PATH}" || true
