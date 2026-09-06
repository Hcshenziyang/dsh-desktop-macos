#!/bin/bash
# Compiler setup shared by builds and tests.
DSH_SWIFT_FLAGS=()
DSH_RESOURCE_DIR=""
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/module-cache}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-$CLANG_MODULE_CACHE_PATH}"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFT_MODULECACHE_PATH"
DSH_CLT_SWIFT_INC="/Library/Developer/CommandLineTools/usr/include/swift"
dsh_cleanup_toolchain() {
    if [ -n "$DSH_RESOURCE_DIR" ] && [ -d "$DSH_RESOURCE_DIR" ]; then rm -rf "$DSH_RESOURCE_DIR"; fi
}
trap dsh_cleanup_toolchain EXIT
if [ -f "$DSH_CLT_SWIFT_INC/module.modulemap" ] && [ -f "$DSH_CLT_SWIFT_INC/bridging.modulemap" ]; then
    DSH_RESOURCE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dsh-desktop-crt.XXXXXX")"
    mkdir -p "$DSH_RESOURCE_DIR/usr/lib" "$DSH_RESOURCE_DIR/usr/include"
    ln -s /Library/Developer/CommandLineTools/usr/lib/swift "$DSH_RESOURCE_DIR/usr/lib/swift"
    cp -R "$DSH_CLT_SWIFT_INC" "$DSH_RESOURCE_DIR/usr/include/swift"
    rm -f "$DSH_RESOURCE_DIR/usr/include/swift/module.modulemap"
    DSH_SWIFT_FLAGS=(-Xswiftc -resource-dir -Xswiftc "$DSH_RESOURCE_DIR/usr/lib/swift")
fi
DSH_SDK_CANDIDATES=()
if [ -n "${SDKROOT:-}" ]; then
    DSH_SDK_CANDIDATES+=("$SDKROOT")
else
    DSH_DEFAULT_SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
    if [ -n "$DSH_DEFAULT_SDK" ]; then DSH_SDK_CANDIDATES+=("$DSH_DEFAULT_SDK"); fi
    for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk; do
        if [ -d "$sdk" ] && [ "$sdk" != "$DSH_DEFAULT_SDK" ]; then DSH_SDK_CANDIDATES+=("$sdk"); fi
    done
fi
if [ "${#DSH_SDK_CANDIDATES[@]}" -eq 0 ]; then
    echo "No macOS SDK found. Install Xcode Command Line Tools." >&2
    exit 1
fi
DSH_SPM_FLAGS=(--disable-sandbox --cache-path "$PWD/.build/swiftpm-cache"
               --config-path "$PWD/.build/swiftpm-config" --security-path "$PWD/.build/swiftpm-security")
