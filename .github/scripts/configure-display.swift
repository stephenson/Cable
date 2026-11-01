import CoreGraphics

let display = CGMainDisplayID()
let modes = CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] ?? []
guard let mode = modes.first(where: { $0.width == 1920 && $0.height == 1080 }) else {
    fatalError("1920×1080 is unavailable. Display modes: \(modes.map { "\($0.width)×\($0.height)" })")
}
let result = CGDisplaySetDisplayMode(display, mode, nil)
precondition(result == .success, "Could not configure the display: \(result)")
let bounds = CGDisplayBounds(display)
precondition(bounds.width == 1920 && bounds.height == 1080, "Unexpected display bounds: \(bounds)")
print("Configured UI test display: 1920×1080")
