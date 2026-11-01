import AppKit
import SwiftUI

struct ScreenArrangement {
    let sizes: [CGSize]
    var labelHeight: CGFloat { sizes.isEmpty ? 0 : 28 }

    init(canvases: [CGSize]) {
        sizes = canvases.map { CGSize(width: 700 * $0.width / $0.height, height: 700) }
    }

    var canvasSize: CGSize? {
        guard !sizes.isEmpty else { return nil }
        return CGSize(width: sizes.reduce(0) { $0 + $1.width }, height: 700 + labelHeight)
    }

    func scale(in bounds: CGSize) -> CGFloat {
        guard let canvasSize else { return 1 }
        return min(bounds.width / canvasSize.width, max(0, bounds.height - labelHeight) / 700)
    }
}

enum WindowSizing {
    static func fit(_ window: NSWindow, to canvas: CGSize?, preservingHeight: Bool = false) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        window.styleMask.remove(.fullSizeContentView)
        window.contentAspectRatio = canvas ?? .zero
        guard let screen = window.screen ?? NSScreen.main else { return }
        let available = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        let availableContent = window.contentRect(forFrameRect: available).size
        let current = window.contentRect(forFrameRect: window.frame).size
        let source = canvas ?? CGSize(width: 420, height: 700)
        let longestSide = canvas == nil ? 700 : max(current.width, current.height)
        let scale = min(
            preservingHeight ? current.height / source.height : longestSide / max(source.width, source.height),
            availableContent.width / source.width,
            availableContent.height / source.height
        )
        let content = NSRect(origin: .zero, size: CGSize(width: source.width * scale, height: source.height * scale))
        var frame = window.frameRect(forContentRect: content)
        frame.origin = NSPoint(x: window.frame.midX - frame.width / 2, y: window.frame.midY - frame.height / 2)
        frame.origin.x = min(max(frame.minX, available.minX), available.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, available.minY), available.maxY - frame.height)
        window.setFrame(frame, display: true)
    }
}

struct WindowFit: NSViewRepresentable {
    let canvas: CGSize?
    let deviceCount: Int

    func makeNSView(context: Context) -> WindowFitView { WindowFitView() }

    func updateNSView(_ nsView: WindowFitView, context: Context) {
        nsView.update(canvas: canvas, deviceCount: deviceCount)
    }
}

final class WindowFitView: NSView {
    private var canvas: CGSize?
    private var deviceCount = 0
    private var observer: NSObjectProtocol?

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func update(canvas: CGSize?, deviceCount: Int) {
        guard self.canvas != canvas || self.deviceCount != deviceCount else { return }
        let preservingHeight = self.deviceCount > 0 && deviceCount > 0 && self.deviceCount != deviceCount
        self.canvas = canvas
        self.deviceCount = deviceCount
        fit(preservingHeight: preservingHeight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard let window else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            self?.fit()
        }
        fit()
    }

    private func fit(preservingHeight: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            WindowSizing.fit(window, to: self.canvas, preservingHeight: preservingHeight)
        }
    }
}
