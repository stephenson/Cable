import AppKit
import AVFoundation
@testable import CableTests

@main
struct WindowSizingTests {
    static func main() {
        _ = NSApplication.shared
        let offline = AndroidCapture(resources: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let capture = Capture(android: offline)
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        capture.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        switch authorization {
        case .notDetermined:
            precondition(capture.state == .setup && !capture.requestingPermission, "First launch must explain access before requesting permission")
            precondition(capture.devices.isEmpty)
        case .denied, .restricted:
            precondition(capture.state == .permission, "Denied access must show recovery instructions")
        default:
            precondition(capture.state != .setup, "Authorized users must skip setup")
        }
        capture.stop()
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 420, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let preview = WindowFitView()
        window.contentView = preview

        func show(_ size: CGSize?, modelID: String? = nil) {
            let canvas = size.map { DeviceFrame.matching(modelID: modelID, screenSize: $0).canvasSize }
            preview.update(canvas: canvas, deviceCount: size == nil ? 0 : 1)
        }

        func settle() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        func contentSize() -> CGSize {
            window.contentLayoutRect.size
        }

        func checkFit(width: CGFloat, height: CGFloat, canvas: CGSize? = nil) {
            let content = contentSize()
            let margin = min(width, height) * 0.27
            let expected = canvas ?? CGSize(width: width + margin, height: height + margin)
            precondition(abs(content.width * expected.height - content.height * expected.width) < max(expected.width, expected.height) * 1.5, "Window \(content) does not match padded frame \(expected)")
            let visible = window.screen!.visibleFrame
            precondition(visible.insetBy(dx: -1, dy: -1).contains(window.frame), "Window extends off screen")
            precondition(abs(window.contentAspectRatio.width / window.contentAspectRatio.height - expected.width / expected.height) < 0.00001, "Manual resizing is not aspect locked to the padded frame")
        }

        show(CGSize(width: 1170, height: 2532))
        settle()
        checkFit(width: 1170, height: 2532)
        let portrait = contentSize()
        precondition(portrait.height > portrait.width)

        show(CGSize(width: 2532, height: 1170))
        settle()
        checkFit(width: 2532, height: 1170)
        precondition(abs(contentSize().width - portrait.height) < 2, "Rotation changed the longest side unnecessarily")

        let manuallySized = NSRect(origin: window.frame.origin, size: CGSize(width: 500, height: 500 * 1485.9 / 2847.9))
        window.setFrame(window.frameRect(forContentRect: manuallySized), display: false)
        show(CGSize(width: 2532, height: 1170))
        settle()
        precondition(abs(contentSize().width - 500) < 2, "Unchanged dimensions overrode a manual resize")

        window.setFrame(NSRect(x: -200, y: -200, width: 6000, height: 6000), display: false)
        show(CGSize(width: 2048, height: 2732))
        settle()
        checkFit(width: 2048, height: 2732)

        show(CGSize(width: 1398, height: 2034))
        settle()
        checkFit(width: 1398, height: 2034)
        show(CGSize(width: 1398, height: 2034), modelID: "iPhone19,4")
        settle()
        checkFit(width: 1398, height: 2034, canvas: CGSize(width: 1793.64, height: 2369.64))
        let cover = DeviceFrame.matching(modelID: "iPhone19,4", screenSize: CGSize(width: 1398, height: 2034))
        precondition(cover.corners.topLeading == 24 && cover.corners.topTrailing == 177, "Duo cover must retain asymmetric corners")

        show(CGSize(width: 2853, height: 2007), modelID: "iPhone19,4")
        settle()
        checkFit(width: 2853, height: 2007, canvas: CGSize(width: 3316.26, height: 2470.26))
        let unfolded = DeviceFrame.matching(modelID: "iPhone19,4", screenSize: CGSize(width: 2853, height: 2007))
        precondition(unfolded.corners.topLeading == 165 && unfolded.corners.topTrailing == 165, "Duo unfolding must switch display profiles")
        let layout = unfolded.layout(in: window.contentLayoutRect)
        precondition(layout.body.minX > 0 && layout.body.minY > 0 && window.contentLayoutRect.contains(layout.body), "Phone frame must retain padding on every side")
        precondition(abs(layout.screen.width / layout.screen.height - 2853.0 / 2007.0) < 0.00001, "Video must not stretch to match its bezel")

        let arrangement = ScreenArrangement(canvases: [CGSize(width: 320, height: 700), CGSize(width: 800, height: 600)])
        let combined = arrangement.canvasSize!
        precondition(abs(combined.width - 1253.333333) < 0.001 && combined.height == 728)
        precondition(arrangement.sizes.allSatisfy { $0.height == 700 })
        precondition(ScreenArrangement(canvases: []).canvasSize == nil)
        let beforeAdding = contentSize()
        preview.update(canvas: combined, deviceCount: 2)
        settle()
        precondition(abs(contentSize().height - beforeAdding.height) < 2, "Adding a device should preserve row height when space permits")
        checkFit(width: combined.width, height: combined.height, canvas: combined)
        let unchanged = contentSize()
        preview.update(canvas: combined, deviceCount: 2)
        settle()
        precondition(contentSize() == unchanged, "Unchanged device rows must preserve manual sizing")
        let crowded = ScreenArrangement(canvases: Array(repeating: CGSize(width: 600, height: 800), count: 6)).canvasSize!
        preview.update(canvas: crowded, deviceCount: 6)
        settle()
        checkFit(width: crowded.width, height: crowded.height, canvas: crowded)

        show(nil)
        settle()
        precondition(window.contentAspectRatio == .zero, "Disconnect left the window aspect locked")
        precondition(abs(contentSize().width - 420) < 2 && abs(contentSize().height - 700) < 2, "Disconnect did not restore the welcome size")
        window.orderFront(nil)
        for _ in 0..<20 {
            window.setFrame(NSRect(x: 2200, y: 100, width: 2400, height: 1500), display: true)
            settle()
            let frame = window.frame
            precondition([frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite), "Screen adjustment produced an invalid window frame")
            WindowSizing.fit(window, to: nil)
            precondition(abs(contentSize().width - 420) < 2 && abs(contentSize().height - 700) < 2, "Screen recovery did not restore the welcome size")
        }
        print("PASS: 20 disconnected-window off-screen resize and recovery cycles")
        window.close()
        print("PASS: single and multiple device sizing, rotation, manual resize, display bounds, Duo folding, and disconnect")
    }
}
