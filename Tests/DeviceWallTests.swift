import AppKit
import AVFoundation
import SwiftUI
@testable import CableTests

@main
struct DeviceWallTests: App {
    private let android: AndroidCapture
    private let capture: Capture
    private let suite = "CableWallTests.\(UUID().uuidString)"

    init() {
        android = AndroidCapture()
        capture = Capture(android: android, preferences: UserDefaults(suiteName: suite)!)
    }

    var body: some Scene {
        Window("Device wall test", id: "test") {
            ContentView(capture: capture)
                .task {
                    await Self.runTests(android: android, capture: capture, suite: suite)
                    NSApp.terminate(nil)
                }
        }
        .defaultSize(width: 700, height: 700)
    }

    @MainActor static func runTests(android: AndroidCapture, capture: Capture, suite: String) async {
        defer { UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite) }
        let sources = [AndroidDevice(serial: "A", authorized: true, name: "First"),
                       AndroidDevice(serial: "B", authorized: true, name: "Second")]
        let portrait = sample(configuration: "AAAAAWdCwAvaGFbARAAAAwAEAAADAMo8UKqAAAAAAWjOD8g=", frame: "AAABZYiEOhGKAAIRccAAQDI4AAg0ycnJycnXXXXXXXXXXXXXXXXXXXXXXXXgAAABZQ+IhDoRigACEXHAAEAyOAAINMnJycnJ1111111111111111111111114A==")
        let landscape = sample(configuration: "AAAAAWdCwAvaCjbARAAAAwAEAAADAMo8UKqAAAAAAWjOD8g=", frame: "AAABZYiEOhGKAAISkcAAQs44AAguScnJycnJycnJ111111111111111111111111111111111111111111111111114=")
        android.onDevices?(sources)
        await settle()
        android.onEvent?("A", .frame(portrait))
        android.onEvent?("B", .frame(portrait))
        await settle()
        let first = capture.devices[0]
        let second = capture.devices[1]
        let window = NSApp.windows.first { $0.styleMask.contains(.titled) }!
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        await settle()
        precondition(first.videoLayer.frame.height > first.videoLayer.frame.width)
        precondition(abs(first.videoLayer.frame.width - second.videoLayer.frame.width) < 2)

        let originalName = first.customName
        defer { first.rename(to: originalName) }
        let point = NSPoint(x: window.contentLayoutRect.width / 4, y: 18)
        let timestamp = ProcessInfo.processInfo.systemUptime
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: timestamp, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: timestamp + 0.1, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        print("Rename test: active=\(NSApp.isActive), key=\(window.isKeyWindow), content=\(window.contentLayoutRect), point=\(point), hit=\(String(describing: window.contentView?.hitTest(point)))")
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)
        for _ in 0..<20 {
            if window.firstResponder is NSTextView { break }
            await settle()
        }
        await settle()
        guard let editor = window.firstResponder as? NSTextView else {
            let view = window.contentView!
            let image = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: image)
            try! image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/device-wall.png"))
            preconditionFailure("Clicking a device name must focus its text editor")
        }
        editor.selectAll(nil)
        editor.insertText("Front desk", replacementRange: editor.selectedRange())
        window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
        await settle()
        precondition(first.displayName == "Front desk" && second.displayName == "Second", "Clicking a name and pressing Return must rename only that device")

        android.onEvent?("A", .frame(landscape))
        await settle()
        let rotated = first.videoLayer.frame
        let unchanged = second.videoLayer.frame
        precondition(rotated.width > rotated.height, "Rotated screen must redraw its landscape frame")
        precondition(unchanged.height > unchanged.width, "Peer must stay portrait")
        precondition(rotated.width > unchanged.width * 2, "Row must allocate more width to the landscape screen")
        precondition(abs(rotated.width / rotated.height - 160.0 / 96) < 0.01)

        android.onEvent?("A", .authorize)
        await settle()
        precondition(first.canvasSize.height > first.canvasSize.width, "Authorization must not retain a stale landscape canvas")
        precondition(second.state == .live("Second") && second.videoLayer.superlayer != nil)
        android.onEvent?("A", .frame(portrait))
        await settle()
        precondition(capture.devices[0] === first && first.videoLayer.frame.height > first.videoLayer.frame.width)

        android.onDevices?([sources[1]])
        await settle()
        precondition(capture.devices[0] === second && second.videoLayer.superlayer != nil)
        android.onDevices?([])
        await settle()
        precondition(abs(window.contentLayoutRect.width - 420) < 2 && abs(window.contentLayoutRect.height - 700) < 2)
        capture.stop()
        window.close()
        print("PASS: rendered device wall rotates one phone, preserves its peer, and restores welcome after disconnect")
    }

    static func settle() async {
        try! await Task.sleep(for: .milliseconds(300))
    }

    static func sample(configuration: String, frame: String) -> CMSampleBuffer {
        var video = AndroidVideo()
        _ = video.sample(packet: Data(base64Encoded: configuration)!, configuration: true)
        return video.sample(packet: Data(base64Encoded: frame)!, configuration: false)!
    }
}
