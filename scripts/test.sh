#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-toolchain.sh

swift --version
DSH_TEST_HELP="$(swift test --help)"
if [[ "$DSH_TEST_HELP" != *--disable-xctest* ]]; then
    echo "Regression tests require Swift 6 or newer. Select Xcode 16+ or compatible Command Line Tools." >&2
    exit 1
fi

# Command Line Tools ship Swift Testing as a framework outside the SDK.
DSH_TEST_FLAGS=()
DSH_DEVELOPER_DIR="$(xcode-select -p)"
DSH_TEST_FRAMEWORKS="$DSH_DEVELOPER_DIR/Library/Developer/Frameworks"
if [ -d "$DSH_TEST_FRAMEWORKS/Testing.framework" ]; then
    DSH_TEST_FLAGS=(-Xswiftc -F -Xswiftc "$DSH_TEST_FRAMEWORKS"
                    -Xlinker -F -Xlinker "$DSH_TEST_FRAMEWORKS"
                    -Xlinker -rpath -Xlinker "$DSH_TEST_FRAMEWORKS")
    if [ -f "$DSH_DEVELOPER_DIR/Library/Developer/usr/lib/lib_TestingInterop.dylib" ]; then
        DSH_TEST_FLAGS+=(-Xlinker -rpath -Xlinker "$DSH_DEVELOPER_DIR/Library/Developer/usr/lib")
    fi
fi
swift package "${DSH_SPM_FLAGS[@]}" dump-package | python3 scripts/check-boundaries.py
swift test --disable-xctest "${DSH_SPM_FLAGS[@]}" --scratch-path "$PWD/.build/swiftpm/tests" \
    --sdk "${DSH_SDK_CANDIDATES[0]}" ${DSH_SWIFT_FLAGS[@]+"${DSH_SWIFT_FLAGS[@]}"} \
    ${DSH_TEST_FLAGS[@]+"${DSH_TEST_FLAGS[@]}"} "$@"
node Tests/Plugins/plugin-inventory.test.mjs
