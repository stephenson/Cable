import AppKit
import SwiftUI

struct DeviceFrame {
    var screenSize: CGSize
    var bezels: EdgeInsets
    var corners: RectangleCornerRadii

    private init(width: CGFloat, height: CGFloat, bezel: CGFloat, radius: CGFloat, verticalBezel: CGFloat? = nil) {
        screenSize = CGSize(width: width, height: height)
        bezels = EdgeInsets(top: verticalBezel ?? bezel, leading: bezel, bottom: verticalBezel ?? bezel, trailing: bezel)
        corners = RectangleCornerRadii(topLeading: radius, bottomLeading: radius, bottomTrailing: radius, topTrailing: radius)
    }

    static func matching(modelID: String?, screenSize: CGSize) -> DeviceFrame {
        let short = min(screenSize.width, screenSize.height)
        let long = max(screenSize.width, screenSize.height)
        var frame: DeviceFrame
        switch modelID {
        case "iPhone19,4":
            let coverRatio = CGFloat(466) / 678
            let innerRatio = CGFloat(669) / 951
            if abs(short / long - coverRatio) < abs(short / long - innerRatio) {
                frame = DeviceFrame(width: 466, height: 678, bezel: 14, radius: 59)
                frame.bezels.leading = 26
                frame.bezels.trailing = 22
                frame.corners.topLeading = 8
                frame.corners.bottomLeading = 8
            } else {
                frame = DeviceFrame(width: 669, height: 951, bezel: 17, radius: 55)
            }
        case "iPhone19,2", "iPhone18,1", "iPhone18,3", "iPhone17,1":
            frame = DeviceFrame(width: 402, height: 874, bezel: 18, radius: 62)
        case "iPhone19,3", "iPhone18,2", "iPhone17,2":
            frame = DeviceFrame(width: 440, height: 956, bezel: 18, radius: 62)
        case "iPhone18,4":
            frame = DeviceFrame(width: 420, height: 912, bezel: 18, radius: 62)
        case "iPhone17,3", "iPhone16,1":
            frame = DeviceFrame(width: 393, height: 852, bezel: 18, radius: 55)
        case "iPhone17,4", "iPhone16,2":
            frame = DeviceFrame(width: 430, height: 932, bezel: 18, radius: 55)
        case "iPhone15,2", "iPhone15,4":
            frame = DeviceFrame(width: 393, height: 852, bezel: 21, radius: 55)
        case "iPhone15,3", "iPhone15,5":
            frame = DeviceFrame(width: 430, height: 932, bezel: 20, radius: 55)
        case "iPhone18,5", "iPhone17,5", "iPhone14,7", "iPhone14,5", "iPhone14,2":
            frame = DeviceFrame(width: 390, height: 844, bezel: 22, radius: 47.3333)
        case "iPhone14,8", "iPhone14,3":
            frame = DeviceFrame(width: 428, height: 926, bezel: 22, radius: 53.3333)
        case "iPhone13,2", "iPhone13,3":
            frame = DeviceFrame(width: 390, height: 844, bezel: 22, radius: 47)
        case "iPhone13,4":
            frame = DeviceFrame(width: 428, height: 926, bezel: 22, radius: 53)
        case "iPhone14,4", "iPhone13,1":
            frame = DeviceFrame(width: 360, height: 780, bezel: 22, radius: 44)
        case "iPhone12,3", "iPhone11,2", "iPhone10,6", "iPhone10,3":
            frame = DeviceFrame(width: 375, height: 812, bezel: 29, radius: 39)
        case "iPhone12,5", "iPhone11,4", "iPhone11,6":
            frame = DeviceFrame(width: 414, height: 896, bezel: 29, radius: 39)
        case "iPhone12,1", "iPhone11,8":
            frame = DeviceFrame(width: 414, height: 896, bezel: 29, radius: 41.5)
        case "iPhone14,6", "iPhone12,8", "iPhone10,4", "iPhone10,1", "iPhone9,1", "iPhone9,3", "iPhone8,1":
            frame = DeviceFrame(width: 375, height: 667, bezel: 28, radius: 0, verticalBezel: 111)
        case "iPhone10,5", "iPhone10,2", "iPhone9,2", "iPhone9,4", "iPhone8,2":
            frame = DeviceFrame(width: 414, height: 736, bezel: 28, radius: 0, verticalBezel: 111)
        case "iPhone8,4":
            frame = DeviceFrame(width: 320, height: 568, bezel: 28, radius: 0, verticalBezel: 111)
        default:
            frame = DeviceFrame(width: short, height: long, bezel: short * 0.045, radius: short * (short / long > 0.6 ? 0.04 : 0.14))
        }
        if screenSize.width > screenSize.height {
            frame.screenSize = CGSize(width: frame.screenSize.height, height: frame.screenSize.width)
            let bezel = frame.bezels
            frame.bezels = EdgeInsets(top: bezel.leading, leading: bezel.bottom, bottom: bezel.trailing, trailing: bezel.top)
            let corner = frame.corners
            frame.corners = RectangleCornerRadii(topLeading: corner.bottomLeading, bottomLeading: corner.bottomTrailing, bottomTrailing: corner.topTrailing, topTrailing: corner.topLeading)
        }
        let scale = screenSize.width / frame.screenSize.width
        frame.screenSize = screenSize
        frame.bezels = EdgeInsets(top: frame.bezels.top * scale, leading: frame.bezels.leading * scale, bottom: frame.bezels.bottom * scale, trailing: frame.bezels.trailing * scale)
        frame.corners = RectangleCornerRadii(topLeading: frame.corners.topLeading * scale, bottomLeading: frame.corners.bottomLeading * scale, bottomTrailing: frame.corners.bottomTrailing * scale, topTrailing: frame.corners.topTrailing * scale)
        return frame
    }

    var padding: CGFloat { min(screenSize.width, screenSize.height) * 0.09 }

    var canvasSize: CGSize {
        CGSize(width: screenSize.width + bezels.leading + bezels.trailing + padding * 2,
               height: screenSize.height + bezels.top + bezels.bottom + padding * 2)
    }

    func layout(in bounds: CGRect) -> (body: CGRect, screen: CGRect, scale: CGFloat) {
        let canvas = canvasSize
        let scale = min(bounds.width / canvas.width, bounds.height / canvas.height)
        let x = bounds.midX - canvas.width * scale / 2
        let y = bounds.midY - canvas.height * scale / 2
        let body = CGRect(x: x + padding * scale, y: y + padding * scale,
                          width: (canvas.width - padding * 2) * scale, height: (canvas.height - padding * 2) * scale)
        let screen = CGRect(x: body.minX + bezels.leading * scale, y: body.minY + bezels.top * scale,
                            width: screenSize.width * scale, height: screenSize.height * scale)
        return (body, screen, scale)
    }

    func path(in rect: CGRect, scale: CGFloat, outer: Bool = false) -> CGPath {
        let inset = outer ? min(bezels.top, bezels.leading, bezels.bottom, bezels.trailing) : 0
        let radius = RectangleCornerRadii(
            topLeading: (corners.topLeading + inset) * scale,
            bottomLeading: (corners.bottomLeading + inset) * scale,
            bottomTrailing: (corners.bottomTrailing + inset) * scale,
            topTrailing: (corners.topTrailing + inset) * scale
        )
        return UnevenRoundedRectangle(cornerRadii: radius, style: .continuous).path(in: rect).cgPath
    }
}
