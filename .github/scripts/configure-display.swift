import CoreGraphics

let display = CGMainDisplayID()
let modes = CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] ?? []
guard let mode = modes.first(where: { $0.width == 1920 && $0.height == 1080 }) else {
    fatalError("1920×1080 is unavailable. Display modes: \(modes.map { "\($0.width)×\($0.height)" })")
}
var configuration: CGDisplayConfigRef?
precondition(CGBeginDisplayConfiguration(&configuration) == .success)
precondition(CGConfigureDisplayWithDisplayMode(configuration, display, mode, nil) == .success)
precondition(CGCompleteDisplayConfiguration(configuration, .forSession) == .success)
let bounds = CGDisplayBounds(display)
precondition(bounds.width == 1920 && bounds.height == 1080, "Unexpected display bounds: \(bounds)")
print("Configured UI test display: 1920×1080")
