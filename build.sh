#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$ROOT/build}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
APP="$TEMP/Cable.app"
SPARKLE="$OUT/.sparkle"
bash "$ROOT/Installer/sparkle.sh" "$SPARKLE"
mkdir -p "$TEMP/Cable.iconset" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE/LICENSE" "$APP/Contents/Resources/SPARKLE-LICENSE.txt"
for ARCH in arm64 x86_64; do
    xcrun swiftc -O -swift-version 5 -target "$ARCH-apple-macosx14.0" \
        -sdk "$(xcrun --show-sdk-path)" "$ROOT"/Sources/*.swift \
        -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
        -o "$TEMP/Cable-$ARCH"
done
xcrun lipo -create "$TEMP/Cable-arm64" "$TEMP/Cable-x86_64" -output "$APP/Contents/MacOS/Cable"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-$VERSION}" "$APP/Contents/Info.plist"
fi
xcrun swift "$ROOT/Icon.swift" "$TEMP/Cable.iconset"
iconutil -c icns "$TEMP/Cable.iconset" -o "$APP/Contents/Resources/Cable.icns"
bash "$ROOT/Installer/android.sh" "$APP" "$OUT/.android-tools"
SIGN=(--force --options runtime --sign "${CODE_SIGN_IDENTITY:--}")
cp "$ROOT/Cable.entitlements" "$TEMP/entitlements.plist"
if [[ "${CODE_SIGN_IDENTITY:--}" == - ]]; then
    /usr/libexec/PlistBuddy -c 'Add :com.apple.security.cs.disable-library-validation bool true' "$TEMP/entitlements.plist"
else
    SIGN+=(--timestamp)
fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
for COMPONENT in XPCServices/Downloader.xpc XPCServices/Installer.xpc Autoupdate Updater.app; do
    codesign "${SIGN[@]}" --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/$COMPONENT"
done
codesign "${SIGN[@]}" "$FRAMEWORK"
codesign "${SIGN[@]}" --entitlements "$TEMP/entitlements.plist" "$APP"
bash "$ROOT/test.sh" "$APP" "$OUT/.android-tools"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    ditto -c -k --keepParent "$APP" "$TEMP/Cable.zip"
    xcrun notarytool submit "$TEMP/Cable.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
fi
TOOLS="$OUT/.installer-tools"
if [[ ! -x "$TOOLS/bin/python3" ]]; then
    "${PYTHON:-python3}" -m venv "$TOOLS"
fi
"$TOOLS/bin/python3" -c 'import sys; sys.exit("Installer packaging requires Python 3.10+. Recreate build/.installer-tools using PYTHON=/path/to/python3.12.") if sys.version_info < (3, 10) else None'
"$TOOLS/bin/python3" -m pip install --disable-pip-version-check --quiet -r "$ROOT/Installer/requirements.txt"
xcrun swift "$ROOT/Installer/Background.swift" "$TEMP/background.tiff"
"$TOOLS/bin/dmgbuild" -s "$ROOT/Installer/settings.py" -D app="$APP" -D background="$TEMP/background.tiff" "Install Cable" "$OUT/Cable.dmg"
ditto -c -k --keepParent "$APP" "$OUT/Cable.zip"
rm -rf "$OUT/Cable.app"
mv "$APP" "$OUT/Cable.app"
APP="$OUT/Cable.app"
printf '\nBuilt %s\n' "$APP" "$OUT/Cable.dmg" "$OUT/Cable.zip"
