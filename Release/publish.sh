#!/bin/bash
set -euo pipefail
set +x
umask 077

cd "$(dirname "$0")/.."
for name in GH_TOKEN CERTIFICATE_P12 CERTIFICATE_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD SPARKLE_PRIVATE_KEY GITHUB_EVENT_PATH GITHUB_REPOSITORY RELEASE_TEMP; do
    if [[ -z "${!name:-}" ]]; then
        printf 'Missing required setting: %s\n' "$name" >&2
        exit 1
    fi
done
[[ "$GITHUB_REPOSITORY" == stephenson/Cable ]]
[[ "$(jq -r '.action' "$GITHUB_EVENT_PATH")" == published ]]
[[ "$(jq -r '.release.prerelease' "$GITHUB_EVENT_PATH")" == false ]]
TAG="$(jq -er '.release.tag_name' "$GITHUB_EVENT_PATH")"
if [[ ! "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    printf 'Stable releases require a vX.Y.Z tag without leading zeros: %s\n' "$TAG" >&2
    exit 1
fi
export VERSION="${TAG#v}" BUILD_NUMBER="${TAG#v}"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "refs/tags/$TAG^{commit}")" ]]
[[ "$(gh api "repos/$GITHUB_REPOSITORY" --jq '.private')" == false ]]
mkdir "$RELEASE_TEMP"
KEYCHAIN="$RELEASE_TEMP/signing.keychain-db"
ORIGINAL_DEFAULT="$(security default-keychain -d user | sed 's/^ *"//; s/"$//')"
ORIGINAL_KEYCHAINS=()
while IFS= read -r keychain; do
    ORIGINAL_KEYCHAINS+=("$keychain")
done < <(security list-keychains -d user | sed 's/^ *"//; s/"$//')
cleanup() {
    security default-keychain -d user -s "$ORIGINAL_DEFAULT" >/dev/null 2>&1 || true
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1 || true
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    rm -rf "$RELEASE_TEMP"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

read_optional_api() {
    if gh api --include "$1" > "$RELEASE_TEMP/api-response" 2> "$RELEASE_TEMP/api-error"; then
        python3 - "$RELEASE_TEMP/api-response" "$2" <<'PY'
import pathlib
import sys

response = pathlib.Path(sys.argv[1]).read_bytes().replace(b'\r\n', b'\n')
pathlib.Path(sys.argv[2]).write_bytes(response.split(b'\n\n', 1)[1])
PY
    elif head -n 1 "$RELEASE_TEMP/api-response" | grep -Eq '^HTTP/[^ ]+ 404( |\r?$)'; then
        printf 'null\n' > "$2"
    else
        cat "$RELEASE_TEMP/api-error" >&2
        exit 1
    fi
}

check_release_version() {
    gh api --paginate --slurp "repos/$GITHUB_REPOSITORY/releases?per_page=100" > "$RELEASE_TEMP/releases.json"
    python3 - "$RELEASE_TEMP/releases.json" "$VERSION" <<'PY'
import json
import re
import sys

target = tuple(map(int, sys.argv[2].split('.')))
for page in json.load(open(sys.argv[1])):
    for release in page:
        if release['draft'] or release['prerelease']:
            continue
        tag = release['tag_name']
        if not re.fullmatch(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', tag):
            sys.exit(f'Unexpected published stable tag: {tag}')
        version = tuple(map(int, tag[1:].split('.')))
        if version > target:
            sys.exit(f'Refusing release v{sys.argv[2]} because newer release {tag} is published')
PY
    read_optional_api "repos/$GITHUB_REPOSITORY/contents/appcast.xml?ref=updates" "$RELEASE_TEMP/current-feed.json"
    python3 - "$RELEASE_TEMP/current-feed.json" "$VERSION" "$RELEASE_TEMP" <<'PY'
import base64
import json
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

entry = json.load(open(sys.argv[1]))
current = pathlib.Path(sys.argv[3]) / 'current-feed.xml'
if entry is None:
    current.unlink(missing_ok=True)
else:
    if entry.get('type') != 'file' or entry.get('encoding') != 'base64' or not entry.get('sha'):
        sys.exit('Unexpected updates branch appcast response')
    data = base64.b64decode(''.join(entry['content'].split()), validate=True)
    items = ET.fromstring(data).findall('./channel/item')
    if not items:
        sys.exit('Updates branch appcast has no updates')
    target = tuple(map(int, sys.argv[2].split('.')))
    for item in items:
        version = item.findtext('{http://www.andymatuschak.org/xml-namespaces/sparkle}version', '')
        if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', version):
            sys.exit('Updates branch appcast has an invalid version')
        parts = tuple(map(int, version.split('.')))
        width = max(len(parts), len(target))
        existing = parts + (0,) * (width - len(parts))
        proposed = target + (0,) * (width - len(target))
        if existing > proposed:
            sys.exit(f'Refusing regression from updates branch version {version}')
        candidate = pathlib.Path(sys.argv[3]) / 'assets/appcast.xml'
        if existing == proposed and candidate.exists() and candidate.read_bytes() != data:
            sys.exit('Same-version updates branch appcast must match release asset byte-for-byte')
    current.write_bytes(data)
PY
}
check_release_version
gh release view "$TAG" --repo "$GITHUB_REPOSITORY" --json isDraft,isPrerelease,assets > "$RELEASE_TEMP/release.json"
[[ "$(jq -r '.isDraft or .isPrerelease' "$RELEASE_TEMP/release.json")" == false ]]
mkdir "$RELEASE_TEMP/assets"
for asset in Cable.dmg Cable.zip appcast.xml; do
    if jq -e --arg name "$asset" '.assets | any(.name == $name)' "$RELEASE_TEMP/release.json" >/dev/null; then
        gh release download "$TAG" --repo "$GITHUB_REPOSITORY" --pattern "$asset" --dir "$RELEASE_TEMP/assets"
    fi
done
if [[ -f "$RELEASE_TEMP/assets/appcast.xml" ]] && [[ ! -f "$RELEASE_TEMP/assets/Cable.zip" || ! -f "$RELEASE_TEMP/assets/Cable.dmg" ]]; then
    printf 'Published appcast exists without both release archives; refusing to modify this release\n' >&2
    exit 1
fi
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$RELEASE_TEMP/sparkle.key"
unset SPARKLE_PRIVATE_KEY
if [[ ! -f "$RELEASE_TEMP/assets/Cable.zip" || ! -f "$RELEASE_TEMP/assets/Cable.dmg" ]]; then
    printf '%s' "$CERTIFICATE_P12" | base64 --decode > "$RELEASE_TEMP/certificate.p12"
    KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security list-keychains -d user -s "$KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}"
    security default-keychain -d user -s "$KEYCHAIN"
    security import "$RELEASE_TEMP/certificate.p12" -k "$KEYCHAIN" -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
    CODE_SIGN_IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p')"
    if [[ -z "$CODE_SIGN_IDENTITY" || "$CODE_SIGN_IDENTITY" == *$'\n'* || "$CODE_SIGN_IDENTITY" != *"($APPLE_TEAM_ID)" ]]; then
        printf 'P12 must contain exactly one valid Developer ID Application identity for APPLE_TEAM_ID\n' >&2
        exit 1
    fi
    export CODE_SIGN_IDENTITY NOTARY_PROFILE=cable-release
    xcrun notarytool store-credentials "$NOTARY_PROFILE" --keychain "$KEYCHAIN" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" >/dev/null
    rm -f "$RELEASE_TEMP/certificate.p12"
    unset CERTIFICATE_P12 CERTIFICATE_PASSWORD APPLE_APP_PASSWORD KEYCHAIN_PASSWORD
    bash build.sh
    for asset in Cable.zip Cable.dmg; do
        if [[ ! -f "$RELEASE_TEMP/assets/$asset" ]]; then
            cp "build/$asset" "$RELEASE_TEMP/assets/$asset"
        fi
    done
else
    bash Installer/sparkle.sh build/.sparkle
fi
if [[ ! -f "$RELEASE_TEMP/assets/appcast.xml" ]]; then
    mkdir "$RELEASE_TEMP/feed"
    cp "$RELEASE_TEMP/assets/Cable.zip" "$RELEASE_TEMP/feed/Cable.zip"
    build/.sparkle/bin/generate_appcast --ed-key-file "$RELEASE_TEMP/sparkle.key" --maximum-deltas 0 --download-url-prefix "https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/" "$RELEASE_TEMP/feed"
    cp "$RELEASE_TEMP/feed/appcast.xml" "$RELEASE_TEMP/assets/appcast.xml"
fi
python3 - "$RELEASE_TEMP/assets/appcast.xml" "$VERSION" "$GITHUB_REPOSITORY" "$TAG" <<'PY'
import os
import sys
import xml.etree.ElementTree as ET

tree = ET.parse(sys.argv[1])
items = tree.findall('./channel/item')
enclosures = tree.findall('./channel/item/enclosure')
namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
expected = f'https://github.com/{sys.argv[3]}/releases/download/{sys.argv[4]}/Cable.zip'
if len(items) != 1 or len(enclosures) != 1 or enclosures[0].get('url') != expected or items[0].findtext(namespace + 'version') != sys.argv[2] or items[0].findtext(namespace + 'shortVersionString') != sys.argv[2] or not enclosures[0].get(namespace + 'edSignature') or enclosures[0].get('length') != str(os.path.getsize(os.path.join(os.path.dirname(sys.argv[1]), 'Cable.zip'))):
    sys.exit('Appcast must contain one signed ZIP with the release version, public URL, and correct size')
with open(sys.argv[1] + '.signature', 'w') as output:
    output.write(enclosures[0].get(namespace + 'edSignature'))
PY
build/.sparkle/bin/sign_update --verify --ed-key-file "$RELEASE_TEMP/sparkle.key" "$RELEASE_TEMP/assets/Cable.zip" "$(cat "$RELEASE_TEMP/assets/appcast.xml.signature")"
rm -f "$RELEASE_TEMP/sparkle.key" "$RELEASE_TEMP/assets/appcast.xml.signature"
for asset in Cable.dmg Cable.zip appcast.xml; do
    check_release_version
    if ! jq -e --arg name "$asset" '.assets | any(.name == $name)' "$RELEASE_TEMP/release.json" >/dev/null; then
        gh release upload "$TAG" --repo "$GITHUB_REPOSITORY" "$RELEASE_TEMP/assets/$asset"
    fi
done
read_optional_api "repos/$GITHUB_REPOSITORY/git/ref/heads/updates" "$RELEASE_TEMP/updates-ref.json"
if [[ "$(jq -r 'type' "$RELEASE_TEMP/updates-ref.json")" == null ]]; then
    MAIN_SHA="$(gh api "repos/$GITHUB_REPOSITORY/git/ref/heads/main" --jq .object.sha)"
    gh api --method POST "repos/$GITHUB_REPOSITORY/git/refs" -f ref=refs/heads/updates -f sha="$MAIN_SHA" >/dev/null
fi
check_release_version
if [[ -f "$RELEASE_TEMP/current-feed.xml" ]] && cmp -s "$RELEASE_TEMP/current-feed.xml" "$RELEASE_TEMP/assets/appcast.xml"; then
    printf 'Updates branch already serves the verified release appcast\n'
else
    jq -n --arg branch updates --arg message "Publish $TAG appcast" \
        --arg content "$(base64 < "$RELEASE_TEMP/assets/appcast.xml" | tr -d '\n')" \
        --arg sha "$(jq -r '.sha // empty' "$RELEASE_TEMP/current-feed.json")" \
        '{branch: $branch, message: $message, content: $content} + (if $sha == "" then {} else {sha: $sha} end)' > "$RELEASE_TEMP/feed-request.json"
    gh api --method PUT "repos/$GITHUB_REPOSITORY/contents/appcast.xml" --input "$RELEASE_TEMP/feed-request.json" >/dev/null
fi
