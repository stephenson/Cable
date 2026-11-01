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

## If the screen doesn’t appear

Use a data-capable cable, unlock the iPhone, and accept its Trust prompt. Try another USB port or cable. Quit other apps using the iPhone’s capture feed. Check **System Settings → Privacy & Security → Camera** for Cable, then use **Try Again** if shown. The Help menu has these instructions too.

This is viewing only: no remote control, audio playback, or recording. Protected video may be blank. Unplugging one device leaves all other screens running.

## Build

On a Mac with Xcode and Python 3.10 or newer installed, run `bash build.sh` from the repository root. Set `PYTHON=/path/to/python3.12` if `python3` points to an older version. The build bundles checksum-pinned adb 37.0.0 (universal) and scrcpy-server 3.3.3 with their license notices, and signs adb before signing the app. Disk-image packaging installs pinned `dmgbuild` tools into a build-local virtual environment; the first build requires Internet access. If an existing `build/.installer-tools` environment uses older Python, remove that generated environment before rebuilding. Output is in `build/`: a universal `Cable.app`, drag-to-Applications disk image, and ZIP.

The installer opens with a Retina-resolution Cable background, positioned app and Applications icons, and a branded volume icon. Finder layout metadata is generated directly, without Finder automation permissions. Packaging requires `dmgbuild` 1.6.7, which omits the background bookmark record that breaks background rendering on macOS Tahoe 26.2 and later.

The build verifies that the signed app includes the camera and audio-input entitlements required by Hardened Runtime for the iPhone’s combined capture device. Without the camera entitlement, macOS rejects permission requests without showing a prompt. Run `bash test.sh` to check an existing build.

For distribution, supply a Developer ID Application identity through `CODE_SIGN_IDENTITY` and a preconfigured `notarytool` keychain profile through `NOTARY_PROFILE`. The build then notarizes and staples the app before packaging. Apple Developer membership and valid signing credentials are required. Without them, the build remains ad-hoc signed.

## Implementation

SwiftUI window, AVFoundation previews, and the public CoreMediaIO screen-device opt-in. Discovery is limited to external muxed devices, not the Mac webcam or iPhone Continuity Camera. Every iOS device owns a separate AVCaptureSession and configuration queue. Device notifications plus a low-frequency discovery refresh handle delayed USB enumeration and unplug/replug. No public Phone.inc API or MCP access is needed: this is a standalone, local hardware viewer.

Android discovery filters adb's device list to USB transports, excluding wireless connections and emulators. Each authorized device owns an independent scrcpy helper, decoder, reader queue, and preview layer. Unique server sockets and dynamically allocated loopback ports avoid conflicts between devices and other mirroring sessions. Audio and control channels are disabled. Cable converts the server's framed H.264 packets into Core Media samples and displays them using AVSampleBufferDisplayLayer. Updated SPS/PPS configuration handles rotation. Disconnect and quit close only the relevant sockets, stop their helper processes, and remove Cable's own forwarding rules without killing the shared adb daemon.
