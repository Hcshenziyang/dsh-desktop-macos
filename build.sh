#!/bin/bash
# Compile the declared modules, then assemble and ad-hoc sign the app.
set -euo pipefail
cd "$(dirname "$0")"
source scripts/swift-toolchain.sh
APP_NAME="DSH Desktop Community"
APP=".build/${APP_NAME}.app"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)}"
ARCHS="${ARCHS:-arm64 x86_64}"
MACOS_MIN="${MACOS_MIN:-13.0}"
BINARIES=()
for arch in $ARCHS; do
    compiled=false
    for sdk in "${DSH_SDK_CANDIDATES[@]}"; do
        echo "Building $arch modules with $sdk"
        flags=("${DSH_SPM_FLAGS[@]}" --scratch-path "$PWD/.build/swiftpm/$arch"
               --triple "${arch}-apple-macosx${MACOS_MIN}" --sdk "$sdk" -c release
               ${DSH_SWIFT_FLAGS[@]+"${DSH_SWIFT_FLAGS[@]}"})
        if swift build "${flags[@]}" --product DSHLauncher; then
            bin_path="$(swift build "${flags[@]}" --show-bin-path)"
            BINARIES+=("$bin_path/DSHLauncher")
            compiled=true
            break
        fi
    done
    if [ "$compiled" != true ]; then echo "Could not compile for $arch." >&2; exit 1; fi
 done
# Preserve compiler caches and install backups; only replace the generated app.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R Resources/. "$APP/Contents/Resources/"
if [ "${#BINARIES[@]}" -eq 1 ]; then
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/DSHLauncher"
else
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/DSHLauncher"
fi
cp Info.plist "$APP/Contents/Info.plist"
cp LICENSE NOTICE.md "$APP/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -archs "$APP/Contents/MacOS/DSHLauncher"
echo "Built: $APP"
