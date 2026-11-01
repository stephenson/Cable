#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$(cd "${1:-$ROOT/build/.android-tools}" && pwd)"
for FILE in platform-tools.zip scrcpy-server SCRCPY-LICENSE.txt; do
    test -s "$FIXTURES/$FILE" || { printf 'Missing fixture: %s\n' "$FIXTURES/$FILE" >&2; exit 1; }
done
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/bin" "$TEMP/expected"
unzip -oq "$FIXTURES/platform-tools.zip" platform-tools/adb platform-tools/NOTICE.txt -d "$TEMP/expected"
cat > "$TEMP/bin/curl" <<'SH'
#!/bin/bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) OUTPUT="$2"; shift 2 ;;
        https://*) URL="$1"; shift ;;
        *) shift ;;
    esac
done
case "$URL" in
    */platform-tools_r37.0.0-darwin.zip) FILE=platform-tools.zip ;;
    */scrcpy-server-v3.3.3) FILE=scrcpy-server ;;
    */v3.3.3/LICENSE) FILE=SCRCPY-LICENSE.txt ;;
    *) exit 64 ;;
esac
printf '%s\n' "$FILE" >> "$REQUESTS"
case "$MODE" in
    offline) exit 7 ;;
    interrupted) printf partial > "$OUTPUT"; exit 18 ;;
    wrong-sha) printf incorrect > "$OUTPUT" ;;
    valid) cp "$FIXTURES/$FILE" "$OUTPUT" ;;
    *) exit 64 ;;
esac
SH
printf '#!/bin/bash\nexit 0\n' > "$TEMP/bin/codesign"
chmod +x "$TEMP/bin/curl" "$TEMP/bin/codesign"
export FIXTURES
export PATH="$TEMP/bin:$PATH"
install_android() {
    /bin/bash "$ROOT/Installer/android.sh" "$APP" "$CACHE" > "$WORK/install.log" 2>&1
}
verify_installed() {
    cmp "$TEMP/expected/platform-tools/adb" "$APP/Contents/Resources/Android/adb"
    cmp "$TEMP/expected/platform-tools/NOTICE.txt" "$APP/Contents/Resources/Android/ADB-NOTICE.txt"
    cmp "$FIXTURES/scrcpy-server" "$APP/Contents/Resources/Android/scrcpy-server"
    cmp "$FIXTURES/SCRCPY-LICENSE.txt" "$APP/Contents/Resources/Android/SCRCPY-LICENSE.txt"
    test -x "$APP/Contents/Resources/Android/adb"
}
exercise() {
    WORK="$TEMP/$SCENARIO-$TARGET"
    CACHE="$WORK/cache"
    APP="$WORK/Cable.app"
    export REQUESTS="$WORK/requests" MODE=offline
    mkdir -p "$CACHE"
    cp "$FIXTURES/platform-tools.zip" "$FIXTURES/scrcpy-server" "$FIXTURES/SCRCPY-LICENSE.txt" "$CACHE/"
    : > "$REQUESTS"
    case "$SCENARIO" in
        offline)
            install_android
            test ! -s "$REQUESTS"
            verify_installed
            ;;
        corrupt)
            printf corrupt > "$CACHE/$TARGET"
            MODE=valid install_android
            test "$(cat "$REQUESTS")" = "$TARGET"
            cmp "$FIXTURES/$TARGET" "$CACHE/$TARGET"
            verify_installed
            ;;
        interrupted|wrong-sha)
            rm "$CACHE/$TARGET"
            if MODE="$SCENARIO" install_android; then
                printf 'Unexpected installation success\n' >&2
                return 1
            fi
            test ! -e "$CACHE/$TARGET"
            test ! -e "$APP/Contents/Resources/Android/adb"
            test ! -e "$APP/Contents/Resources/Android/scrcpy-server"
            test ! -e "$APP/Contents/Resources/Android/SCRCPY-LICENSE.txt"
            MODE=valid install_android
            cmp "$FIXTURES/$TARGET" "$CACHE/$TARGET"
            verify_installed
            ;;
    esac
}
FAILURES=0
for SCENARIO in offline corrupt interrupted wrong-sha; do
    for TARGET in platform-tools.zip scrcpy-server SCRCPY-LICENSE.txt; do
        set +e
        (set -e; exercise)
        STATUS=$?
        set -e
        if [[ "$STATUS" -eq 0 ]]; then
            printf 'PASS: %s %s\n' "$SCENARIO" "$TARGET"
        else
            printf 'FAIL: %s %s\n' "$SCENARIO" "$TARGET" >&2
            cat "$TEMP/$SCENARIO-$TARGET/install.log" >&2
            FAILURES=$((FAILURES + 1))
        fi
        if [[ "$SCENARIO" == offline ]]; then break; fi
    done
done
test "$FAILURES" -eq 0
