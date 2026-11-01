# Cable

Your phone. Right here. A tiny native Mac app that automatically displays a USB-connected iPhone, iPad, or Android phone. No picker, account, recording, or phone app to install.

## Install

Requires macOS 14 Sonoma or later. Supports Apple silicon and Intel Macs.

1. Open `Cable.dmg` and drag **Cable** to **Applications**.
2. Open Cable, click **Allow screen access**, and approve macOS’s Camera permission. Cable explains why it needs this before asking. Already-authorized installations skip this step.
3. Connect your iPhone using a USB data cable, unlock it, and tap **Trust** if asked.

That’s it. The screen appears automatically, fits the window without cropping, and reconnects when you plug back in. Use the green window button for full screen. Close the window to quit.

### Android

Requires Android 5 or later. Open **Cable → About Cable** for the short setup guide:

1. Settings → About phone → tap **Build number** seven times (Samsung: **Software information → Build number**).
2. In **Developer options**, enable **USB debugging**.
3. Connect with a USB data cable, unlock, and accept **Allow USB debugging**. Choose **Always allow from this computer** for automatic reconnection.

Android mirroring does not need macOS Camera permission. Cable bundles adb and the scrcpy server; no Homebrew or separate Mac installation is needed. A temporary helper runs on the phone while connected, without installing an Android app. The feed uses a local adb USB tunnel, not Wi-Fi. Android uses a neutral phone outline rather than guessing physical model dimensions. Disable USB debugging afterward if you no longer need it. Only authorize computers you trust.

### Multiple devices

All connected iPhones, iPads, and Android devices appear side by side in the same window, including mixed platforms. Each has its own stream and phone frame. Click the name below any screen to rename it. Press Return or click away to save; Escape cancels. Clear the name to restore the original. Names are remembered on this Mac after reconnecting or reopening Cable; the phone itself is not renamed. Drag a phone frame onto another phone to reorder the row. Names are only for renaming, not dragging. The target gets a mint outline; the order changes when you drop, not while hovering. Order is remembered on this Mac, including across reconnects and app restarts. Previously unseen devices appear on the right. Rotation and connection errors affect only that device. A phone waiting for USB debugging approval gets its own tile rather than blocking other screens. Use **Help → Allow iPhone Screen Access** to enable iPhone capture while Android screens are already open.

The live screen sits inside a dark device outline with continuous rounded corners and padding around the phone. Recognized `AVCaptureDevice.modelID` identifiers use bezel and corner proportions based on Xcode 27.1 Simulator device profiles and DeviceKit chrome metadata, not a claim of exact physical CAD dimensions. iPhone Duo (`iPhone19,4`) switches between its asymmetric cover-screen profile and its unfolded display profile using the incoming aspect ratio. Generic or unknown model IDs use a neutral outline; a display resolution alone is never treated as proof of a particular iPhone model. No additional notch or Dynamic Island is drawn over the captured screen.

The window automatically fits the entire padded row when streams become available, rotate, or fold. Adding or removing a device preserves the row height where space permits; the whole row scales down to fit your Mac’s available screen space. Rotation preserves the window’s longest side where possible. Manual resizing keeps the row’s aspect ratio. Full-screen mode stays full screen; leaving it fits the window to the latest dimensions. Disconnecting the last device restores the welcome window.

Local builds are ad-hoc signed, not notarized. macOS may block a downloaded copy. After trying to open it, go to **System Settings → Privacy & Security → Open Anyway**, then confirm. Only do this for a build you trust. A notarized release avoids this extra step.

### Updates

Cable uses Sparkle’s standard update prompts. Automatic update checks are opt-in through Sparkle’s permission prompt; you can always use **Cable → Check for Updates…** manually. Updates are signed, downloaded over HTTPS, and installed by Sparkle rather than a custom updater.

Version 1.2.1 has no updater. Install an updater-enabled release manually once; subsequent versions can update in the app. Source, official downloads, and the update feed live in the public [`stephenson/Cable`](https://github.com/stephenson/Cable/releases) repository. Updates become available after the release workflow succeeds, not immediately when a release is published.

## If the screen doesn’t appear

Use a data-capable cable, unlock the iPhone, and accept its Trust prompt. Try another USB port or cable. Quit other apps using the iPhone’s capture feed. Check **System Settings → Privacy & Security → Camera** for Cable, then use **Try Again** if shown. The Help menu has these instructions too.

This is viewing only: no remote control, audio playback, or recording. Protected video may be blank. Unplugging one device leaves all other screens running.

## Build

On a Mac with Xcode and Python 3.10 or newer installed, run `bash build.sh` from the repository root. Set `PYTHON=/path/to/python3.12` if `python3` points to an older version. The build bundles checksum-pinned adb 37.0.0 (universal) and scrcpy-server 3.3.3 with their license notices, and signs adb before signing the app. Disk-image packaging installs pinned `dmgbuild` tools into a build-local virtual environment; the first build requires Internet access. If an existing `build/.installer-tools` environment uses older Python, remove that generated environment before rebuilding. Output is in `build/`: a universal `Cable.app`, drag-to-Applications disk image, and ZIP.

The installer opens with a Retina-resolution Cable background, positioned app and Applications icons, and a branded volume icon. Finder layout metadata is generated directly, without Finder automation permissions. Packaging requires `dmgbuild` 1.6.7, which omits the background bookmark record that breaks background rendering on macOS Tahoe 26.2 and later.

The build verifies that the signed app includes the camera and audio-input entitlements required by Hardened Runtime for the iPhone’s combined capture device. Without the camera entitlement, macOS rejects permission requests without showing a prompt. Run `bash test.sh` to check an existing build.

For distribution, supply a Developer ID Application identity through `CODE_SIGN_IDENTITY` and a preconfigured `notarytool` keychain profile through `NOTARY_PROFILE`. The build then notarizes and staples the app before packaging. Apple Developer membership and valid signing credentials are required. Without them, the build remains ad-hoc signed.

## Publishing releases

Release setup:

1. Keep `stephenson/Cable` public so Sparkle can download release assets without credentials. No separate update repository or personal access token is needed; CI uses the repository’s `GITHUB_TOKEN` with Contents write permission.
2. The Sparkle EdDSA key is already configured: its public key is committed as `SUPublicEDKey` in `Info.plist`, and `SPARKLE_PRIVATE_KEY` is a repository secret. Back up the existing private key securely; do not generate a replacement for ordinary releases. If another export is needed, use `build/.sparkle/bin/generate_keys --account inc.phone.cable -x /secure/path/key`. Keep the same key across releases and never commit the private key.
3. Confirm `SUFeedURL` is `https://raw.githubusercontent.com/stephenson/Cable/updates/appcast.xml`.
4. The **release** GitHub environment is already created. Add the Apple signing secrets below there; required reviewer approval and deployment tag restrictions are recommended. The existing repository-level `SPARKLE_PRIVATE_KEY` secret is available to the workflow; avoid adding an environment secret of the same name unless it contains the same key.

| Secret | Value |
| --- | --- |
| `CERTIFICATE_P12` | Base64-encoded P12 containing the Developer ID Application certificate and private key. On macOS: `base64 -i certificate.p12 \| pbcopy`. |
| `CERTIFICATE_PASSWORD` | Password protecting the P12. |
| `APPLE_ID` | Apple account authorized to notarize. |
| `APPLE_TEAM_ID` | Developer team ID matching the signing certificate. |
| `APPLE_APP_PASSWORD` | Apple app-specific password for notarization. |
| `SPARKLE_PRIVATE_KEY` | Already configured repository secret containing the existing exported Sparkle private key, matching the bundled public key. |

To publish, commit the finished changes, tag that commit with a stable version such as `v1.2.2`, push the tag, and publish its GitHub release in `stephenson/Cable`. Creating a draft alone does not build anything; prereleases are skipped. No push or pull-request builds are configured.

The release workflow checks out the exact tag and validates the tag and required secrets before building. Both `VERSION` and `BUILD_NUMBER` are set to the tag without `v` (for example, `1.2.2`), so retries and workflow run ordering do not change update ordering. The old `1.2.1` build number `11` is not part of an existing Sparkle update channel; those installations require the manual install described above.

CI uses Python 3.12, imports the certificate into a temporary dedicated keychain, configures notarization, builds and notarizes the app, and generates a signed ZIP appcast with Sparkle 2.10.1’s `generate_appcast`, with delta updates disabled. It uploads `Cable.dmg`, `Cable.zip`, and `appcast.xml` to the triggering release, then updates the stable feed on the `updates` branch last using GitHub’s Contents API and the existing file’s SHA for optimistic concurrency. There is no mirror repository, personal access token, external hosting, deployment action, or manual feed-publishing step.

The stable raw feed URL does not follow GitHub’s latest-release pointer. Publishing a release starts CI; the existing feed keeps serving the previous working update while CI builds, uploads, and verifies the new assets. Only after those steps succeed does CI commit the new appcast to `updates`. A failed build or upload leaves the old feed working. On the first successful release, CI creates `updates` from the current `main` ref if needed, then adds the feed; before that first publication there is no feed yet. CI never modifies `main`, and no workflow runs on updates-branch pushes.

Retries reuse existing assets and verify the ZIP’s Sparkle signature, feed version, URL, and size. Only missing assets are uploaded; published assets are never overwritten. Partial archive uploads can resume, but a release with an appcast and missing archives is rejected. A run refuses to proceed if a higher stable version has already been published or the `updates` feed advertises a higher version. An equal feed version is allowed only when its bytes match the verified release appcast; an already published identical feed is a no-op. Concurrent feed changes cause the Contents API write to fail rather than overwrite a newer feed; retry after reviewing the conflict. Only HTTP 404 is treated as an absent branch or feed; other API failures stop publication. Release runs are serialized; do not publish or edit releases or the feed manually while CI is running. Correct an already published bad artifact with a higher version instead of moving tags or rolling the feed back.

## Implementation

SwiftUI window, AVFoundation previews, and the public CoreMediaIO screen-device opt-in. Discovery is limited to external muxed devices, not the Mac webcam or iPhone Continuity Camera. Every iOS device owns a separate AVCaptureSession and configuration queue. Device notifications plus a low-frequency discovery refresh handle delayed USB enumeration and unplug/replug. No public Phone.inc API or MCP access is needed: this is a standalone, local hardware viewer.

Android discovery filters adb's device list to USB transports, excluding wireless connections and emulators. Each authorized device owns an independent scrcpy helper, decoder, reader queue, and preview layer. Unique server sockets and dynamically allocated loopback ports avoid conflicts between devices and other mirroring sessions. Audio and control channels are disabled. Cable converts the server's framed H.264 packets into Core Media samples and displays them using AVSampleBufferDisplayLayer. Updated SPS/PPS configuration handles rotation. Disconnect and quit close only the relevant sockets, stop their helper processes, and remove Cable's own forwarding rules without killing the shared adb daemon.
