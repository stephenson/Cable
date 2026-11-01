import AppKit

let size = NSSize(width: 680, height: 460)
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1360, pixelsHigh: 920,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let white = NSColor(white: 0.96, alpha: 1)
let secondary = NSColor(white: 0.68, alpha: 1)
NSColor(red: 0.075, green: 0.082, blue: 0.087, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

func text(_ value: String, x: CGFloat, top: CGFloat, width: CGFloat, font: NSFont, color: NSColor, tracking: CGFloat = 0) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byClipping
    paragraph.alignment = .center
    (value as NSString).draw(
        in: NSRect(x: x, y: size.height - top - 40, width: width, height: 40),
        withAttributes: [.font: font, .foregroundColor: color, .kern: tracking, .paragraphStyle: paragraph]
    )
}

text("Your phone. Right here.", x: 48, top: 78, width: 584, font: .systemFont(ofSize: 32, weight: .semibold), color: white, tracking: -1)
text("Drag Cable to Applications. Then plug in.", x: 48, top: 125, width: 584, font: .systemFont(ofSize: 15), color: secondary)

secondary.withAlphaComponent(0.7).setStroke()
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 322, y: 216))
arrow.line(to: NSPoint(x: 358, y: 216))
arrow.move(to: NSPoint(x: 348, y: 226))
arrow.line(to: NSPoint(x: 358, y: 216))
arrow.line(to: NSPoint(x: 348, y: 206))
arrow.lineWidth = 2
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.stroke()

NSColor(white: 0.88, alpha: 1).setFill()
for center in [174.0, 506.0] {
    NSBezierPath(roundedRect: NSRect(x: center - 66, y: 132, width: 132, height: 26), xRadius: 6, yRadius: 6).fill()
}

NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .tiff, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
