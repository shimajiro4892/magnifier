import AppKit
import CoreGraphics

/// A physical display described in both AppKit (points) and native (pixels) coordinates.
struct DisplayGeometry: Equatable {
    let displayID: CGDirectDisplayID
    /// Frame in AppKit global coordinates: origin is the bottom-left corner of the main display, unit is points.
    let frame: CGRect
    /// Native pixel dimensions of the display mode.
    let pixelSize: CGSize

    var scaleFactor: CGFloat {
        guard frame.width > 0, frame.height > 0 else { return 1 }
        return pixelSize.width / frame.width
    }

    static func all() -> [DisplayGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let pixelWidth = CGFloat(CGDisplayPixelsWide(displayID))
            let pixelHeight = CGFloat(CGDisplayPixelsHigh(displayID))
            let pixelSize: CGSize
            if pixelWidth > 0, pixelHeight > 0 {
                pixelSize = CGSize(width: pixelWidth, height: pixelHeight)
            } else {
                pixelSize = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                                   height: screen.frame.height * screen.backingScaleFactor)
            }
            return DisplayGeometry(displayID: displayID, frame: screen.frame, pixelSize: pixelSize)
        }
    }

    static func containing(_ point: CGPoint) -> DisplayGeometry? {
        let displays = all()
        if let exact = displays.first(where: { $0.frame.contains(point) }) {
            return exact
        }
        return displays.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }
}
