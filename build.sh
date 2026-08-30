#!/bin/bash
# Build and ad-hoc sign a universal DSH Desktop Community app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DSH Desktop Community"
APP=".build/${APP_NAME}.app"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)}"
ARCHS="${ARCHS:-arm64 x86_64}"
MACOS_MIN="${MACOS_MIN:-13.0}"

# Keep compiler caches inside the build directory unless the caller supplied a location.
# GUI/sandboxed terminals may not be allowed to write Swift's default ~/.cache path.
MODULE_CACHE="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/module-cache}"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-$MODULE_CACHE}"

RESDIR_FLAGS=()
PATCHED_RESOURCE_DIR=""
CLT_SWIFT_INC="/Library/Developer/CommandLineTools/usr/include/swift"

cleanup() {
    if [ -n "$PATCHED_RESOURCE_DIR" ] && [ -d "$PATCHED_RESOURCE_DIR" ]; then
        rm -rf "$PATCHED_RESOURCE_DIR"
    fi
}
trap cleanup EXIT

# Some Command Line Tools releases contain two SwiftBridging module maps.
# Use a temporary resource directory without modifying the system installation.
if [ -f "$CLT_SWIFT_INC/module.modulemap" ] && [ -f "$CLT_SWIFT_INC/bridging.modulemap" ]; then
    echo "==> Applying Command Line Tools SwiftBridging workaround"
    PATCHED_RESOURCE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dsh-desktop-crt.XXXXXX")"
    mkdir -p "$PATCHED_RESOURCE_DIR/usr/lib" "$PATCHED_RESOURCE_DIR/usr/include"
    ln -s /Library/Developer/CommandLineTools/usr/lib/swift "$PATCHED_RESOURCE_DIR/usr/lib/swift"
    cp -R "$CLT_SWIFT_INC" "$PATCHED_RESOURCE_DIR/usr/include/swift"
    rm -f "$PATCHED_RESOURCE_DIR/usr/include/swift/module.modulemap"
    RESDIR_FLAGS=(-resource-dir "$PATCHED_RESOURCE_DIR/usr/lib/swift")
fi

echo "==> Cleaning build directory"
rm -rf .build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/bin \
    "$CLANG_MODULE_CACHE_PATH" "$SWIFT_MODULECACHE_PATH"

echo "==> Copying app icon"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Compiling for: $ARCHS"
SDK_CANDIDATES=()
if [ -n "${SDKROOT:-}" ]; then
    SDK_CANDIDATES+=("$SDKROOT")
else
    DEFAULT_SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
    if [ -n "$DEFAULT_SDK" ]; then SDK_CANDIDATES+=("$DEFAULT_SDK"); fi
    for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk; do
        if [ -d "$sdk" ] && [ "$sdk" != "$DEFAULT_SDK" ]; then
            SDK_CANDIDATES+=("$sdk")
        fi
    done
fi
if [ "${#SDK_CANDIDATES[@]}" -eq 0 ]; then
    echo "No macOS SDK found. Install Xcode Command Line Tools." >&2
    exit 1
fi

BINARIES=()
for arch in $ARCHS; do
    binary=".build/bin/DSHLauncher-${arch}"
    compiled=false
    for sdk in "${SDK_CANDIDATES[@]}"; do
        echo "==> Trying SDK: $sdk"
        if swiftc -parse-as-library -O -swift-version 5 \
            ${RESDIR_FLAGS[@]+"${RESDIR_FLAGS[@]}"} \
            -sdk "$sdk" \
            -target "${arch}-apple-macosx${MACOS_MIN}" \
            -framework SwiftUI -framework AppKit -framework WebKit \
            -o "$binary" Sources/DSHLauncher.swift; then
            compiled=true
            break
        fi
        echo "==> SDK was incompatible with the installed Swift compiler; trying another"
    done
    if [ "$compiled" != true ]; then
        echo "Could not compile for $arch with any installed macOS SDK." >&2
        exit 1
    fi
    BINARIES+=("$binary")
done

if [ "${#BINARIES[@]}" -eq 1 ]; then
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/DSHLauncher"
else
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/DSHLauncher"
fi

echo "==> Assembling app bundle"
cp Info.plist "$APP/Contents/Info.plist"
cp LICENSE NOTICE.md "$APP/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

echo "==> Verifying bundle"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -archs "$APP/Contents/MacOS/DSHLauncher"

echo
echo "Built: $APP"
echo "Open:  open \"$APP\""
