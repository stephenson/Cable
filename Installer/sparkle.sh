#!/bin/bash
set -euo pipefail
CACHE="$1"
mkdir -p "$CACHE"
SHA=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
ARCHIVE="$CACHE/Sparkle.tar.xz"
if ! printf '%s  %s\n' "$SHA" "$ARCHIVE" | shasum -a 256 -c - >/dev/null 2>&1; then
    TEMP="$(mktemp "$CACHE/download.XXXXXX")"
    trap 'rm -f "$TEMP"' EXIT
    curl --fail --location --silent --show-error https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz -o "$TEMP"
    printf '%s  %s\n' "$SHA" "$TEMP" | shasum -a 256 -c -
    mv "$TEMP" "$ARCHIVE"
fi
tar -xf "$ARCHIVE" -C "$CACHE"
