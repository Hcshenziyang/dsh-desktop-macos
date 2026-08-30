#!/bin/bash
# Package an existing app bundle as ZIP and DMG release artifacts.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="DSH Desktop Community"
APP=".build/${APP_NAME}.app"
VERSION="${VERSION:-}"

if [ ! -d "$APP" ] || [ ! -f "$APP/Contents/Info.plist" ]; then
    echo "Missing $APP. Run ./build.sh first." >&2
    exit 1
fi
if [ -z "$VERSION" ]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
fi
if [ -z "$VERSION" ]; then
    echo "Could not determine app version." >&2
    exit 1
fi

DIST=".build/dist"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/dsh-desktop-release.XXXXXX")"
cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

VOLUME_NAME="DSH Desktop Community"
ASSET_PREFIX="DSH-Desktop-Community"
mkdir -p "$DIST" "$STAGING/$VOLUME_NAME"
rm -f "$DIST/${ASSET_PREFIX}-${VERSION}.zip" "$DIST/${ASSET_PREFIX}-${VERSION}.dmg" \
    "$DIST/${ASSET_PREFIX}-latest.zip" "$DIST/${ASSET_PREFIX}-latest.zip.sha256"

ditto "$APP" "$STAGING/$VOLUME_NAME/$APP_NAME.app"
cp README.md LICENSE NOTICE.md "$STAGING/$VOLUME_NAME/"
ln -s /Applications "$STAGING/$VOLUME_NAME/Applications"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/${ASSET_PREFIX}-${VERSION}.zip"
cp "$DIST/${ASSET_PREFIX}-${VERSION}.zip" "$DIST/${ASSET_PREFIX}-latest.zip"
hdiutil create -quiet -volname "$VOLUME_NAME" -srcfolder "$STAGING/$VOLUME_NAME" \
    -ov -format UDZO "$DIST/${ASSET_PREFIX}-${VERSION}.dmg"

(
    cd "$DIST"
    shasum -a 256 "${ASSET_PREFIX}-${VERSION}.zip" "${ASSET_PREFIX}-${VERSION}.dmg" \
        "${ASSET_PREFIX}-latest.zip" > SHA256SUMS.txt
    shasum -a 256 "${ASSET_PREFIX}-latest.zip" > "${ASSET_PREFIX}-latest.zip.sha256"
)

echo "Release artifacts:"
ls -lh "$DIST"
