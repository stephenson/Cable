#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$ROOT/build/Cable.app}"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
bash "$ROOT/Tests/AndroidDependencies.sh" "${2:-$ROOT/build/.android-tools}"
codesign --verify --deep --strict "$APP"
FRAMEWORKS="$APP/Contents/Frameworks"
test -d "$FRAMEWORKS/Sparkle.framework"
test -s "$APP/Contents/Resources/SPARKLE-LICENSE.txt"
for BINARY in "$APP/Contents/MacOS/Cable" "$FRAMEWORKS/Sparkle.framework/Sparkle"; do
    ARCHS=" $(xcrun lipo -archs "$BINARY") "
    [[ "$ARCHS" == *" arm64 "* && "$ARCHS" == *" x86_64 "* ]]
done
otool -L "$APP/Contents/MacOS/Cable" | grep -q '@rpath/Sparkle.framework/'
python3 - "$APP/Contents/Info.plist" <<'PY'
import base64
import plistlib
import sys

with open(sys.argv[1], "rb") as source:
    info = plistlib.load(source)
assert info["SUFeedURL"].startswith("https://")
assert len(base64.b64decode(info["SUPublicEDKey"], validate=True)) == 32
assert info.get("SUAutomaticallyUpdate", False) is False
PY
printf 'PASS: universal Sparkle is embedded, signed, and configured for verified, user-approved updates\n'
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
    -F "$FRAMEWORKS" -framework Sparkle -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -module-name CableTests "$ROOT"/Sources/*.swift -emit-module-path "$TEMP/CableTests.swiftmodule" \
    -o "$TEMP/libCableTests.dylib"
for TEST in "$ROOT"/Tests/*.swift; do
    xcrun swiftc -swift-version 5 -parse-as-library -I "$TEMP" -L "$TEMP" -lCableTests \
        -F "$FRAMEWORKS" -framework Sparkle -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$TEMP" "$TEST" -o "$TEMP/test"
    "$TEMP/test"
done
