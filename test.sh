#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$ROOT/build/Cable.app}"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
codesign --verify --strict "$APP"
codesign --display --entitlements - --xml "$APP" > "$TEMP/entitlements.plist" 2>/dev/null
for RESOURCE in camera audio-input; do
    VALUE="$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.device.$RESOURCE" "$TEMP/entitlements.plist")"
    [[ "$VALUE" == true ]] || { printf 'Missing capture entitlement: %s\n' "$RESOURCE" >&2; exit 1; }
done
printf 'PASS: signed app includes camera and combined-device audio access entitlements\n'
codesign --verify --strict "$APP/Contents/Resources/Android/adb"
"$APP/Contents/Resources/Android/adb" version
test -s "$APP/Contents/Resources/Android/scrcpy-server"
test -s "$APP/Contents/Resources/Android/ADB-NOTICE.txt"
test -s "$APP/Contents/Resources/Android/SCRCPY-LICENSE.txt"
cp -R "$APP/Contents/Resources/Android" "$TEMP/Android"
xcrun swiftc -swift-version 5 -parse-as-library -emit-library -emit-module -enable-testing \
    -module-name CableTests "$ROOT"/Sources/*.swift -emit-module-path "$TEMP/CableTests.swiftmodule" \
    -o "$TEMP/libCableTests.dylib"
for TEST in "$ROOT"/Tests/*.swift; do
    xcrun swiftc -swift-version 5 -parse-as-library -I "$TEMP" -L "$TEMP" -lCableTests \
        -Xlinker -rpath -Xlinker "$TEMP" "$TEST" -o "$TEMP/test"
    "$TEMP/test"
done
