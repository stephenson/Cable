import AppKit

let directory = CommandLine.arguments[1]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        NSAffineTransform(transform: AffineTransform(scale: factor)).concat()
        NSColor(red: 0.10, green: 0.12, blue: 0.13, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 212, yRadius: 212).fill()
        NSColor(red: 0.48, green: 0.88, blue: 0.73, alpha: 1).setStroke()
        let phone = NSBezierPath(roundedRect: NSRect(x: 330, y: 265, width: 364, height: 554), xRadius: 72, yRadius: 72)
        phone.lineWidth = 30
        phone.stroke()
        let cable = NSBezierPath()
        cable.move(to: NSPoint(x: 512, y: 265))
        cable.line(to: NSPoint(x: 512, y: 130))
        cable.lineWidth = 24
        cable.lineCapStyle = .round
        cable.stroke()
        NSColor(red: 0.48, green: 0.88, blue: 0.73, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 466, y: 720, width: 92, height: 18), xRadius: 9, yRadius: 9).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(directory)/icon_\(size)x\(size)\(suffix).png"))
    }
}
