#!/bin/bash
set -euo pipefail
APP="$1"
CACHE="$2"
mkdir -p "$CACHE" "$APP/Contents/Resources/Android"
fetch() {
    local URL="$1" FILE="$2" SHA="$3"
    if [[ ! -f "$FILE" ]]; then
        curl --fail --location --silent --show-error "$URL" -o "$FILE"
    fi
    printf '%s  %s\n' "$SHA" "$FILE" | shasum -a 256 -c -
}
fetch https://dl.google.com/android/repository/platform-tools_r37.0.0-darwin.zip "$CACHE/platform-tools.zip" 094a1395683c509fd4d48667da0d8b5ef4d42b2abfcd29f2e8149e2f989357c7
fetch https://github.com/Genymobile/scrcpy/releases/download/v3.3.3/scrcpy-server-v3.3.3 "$CACHE/scrcpy-server" 7e70323ba7f259649dd4acce97ac4fefbae8102b2c6d91e2e7be613fd5354be0
unzip -oq "$CACHE/platform-tools.zip" platform-tools/adb platform-tools/NOTICE.txt -d "$CACHE"
cp "$CACHE/platform-tools/adb" "$APP/Contents/Resources/Android/adb"
cp "$CACHE/platform-tools/NOTICE.txt" "$APP/Contents/Resources/Android/ADB-NOTICE.txt"
cp "$CACHE/scrcpy-server" "$APP/Contents/Resources/Android/scrcpy-server"
curl --fail --location --silent --show-error https://raw.githubusercontent.com/Genymobile/scrcpy/v3.3.3/LICENSE -o "$APP/Contents/Resources/Android/SCRCPY-LICENSE.txt"
chmod +x "$APP/Contents/Resources/Android/adb"
codesign --force --options runtime --sign "${CODE_SIGN_IDENTITY:--}" "$APP/Contents/Resources/Android/adb"
