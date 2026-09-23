import AppKit
import IOSurface
import QuartzCore

/// Geometry of the lens for a single frame.
struct LensState {
    /// Center of the lens in the host view's coordinate system (points, bottom-left origin).
    var center: CGPoint
    var lensSize: CGSize
    /// Part of the captured display to show, in normalized coordinates with the
    /// origin at the top-left of the display (0 = top, 1 = bottom).
    var cropRect: CGRect
    var shape: LensShape
    var smoothScaling: Bool
    var showBorder: Bool
    var cornerRadius: CGFloat
    var scale: CGFloat
}

/// Draws the magnifier lens. All scaling is done by Core Animation:
/// the newest screen frame is used as layer contents and `contentsRect` selects
/// the region around the cursor, which the GPU then magnifies.
final class LensRenderer {
    private let root = CALayer()
    private let content = CALayer()
    private let border = CAShapeLayer()
    private let shapeMask = CAShapeLayer()

    init(host: CALayer) {
        root.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        root.masksToBounds = false
        root.isHidden = true
        root.shadowColor = NSColor.black.cgColor
        root.shadowOpacity = 0.45
        root.shadowRadius = 16
        root.shadowOffset = CGSize(width: 0, height: -6)

        content.anchorPoint = CGPoint(x: 0, y: 0)
        content.contentsGravity = .resize
        content.masksToBounds = true
        content.isHidden = false

        shapeMask.fillColor = NSColor.black.cgColor
        shapeMask.strokeColor = nil
        content.mask = shapeMask

        border.anchorPoint = CGPoint(x: 0, y: 0)
        border.fillColor = nil
        border.strokeColor = NSColor.white.withAlphaComponent(0.65).cgColor
        border.lineWidth = 1.5

        root.addSublayer(content)
        root.addSublayer(border)
        host.addSublayer(root)
    }

    func setContents(_ surface: IOSurface?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.contents = surface
        CATransaction.commit()
    }

    func update(_ state: LensState) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        root.bounds = CGRect(origin: .zero, size: state.lensSize)
        root.position = state.center
        root.contentsScale = state.scale

        content.frame = root.bounds
        content.contentsScale = state.scale
        // `cropRect` uses a top-left origin (like the display coordinates it comes
        // from), while the layer's own coordinate system is bottom-left oriented,
        // so the vertical origin of `contentsRect` has to be mirrored.
        // Verified by Tools/verify-crop-math.swift.
        content.contentsRect = CGRect(x: state.cropRect.minX,
                                      y: 1 - state.cropRect.maxY,
                                      width: state.cropRect.width,
                                      height: state.cropRect.height)
        content.magnificationFilter = state.smoothScaling ? .linear : .nearest
        content.minificationFilter = state.smoothScaling ? .linear : .nearest

        let path = Self.path(for: state.shape, in: root.bounds, cornerRadius: state.cornerRadius)
        shapeMask.frame = content.bounds
        shapeMask.contentsScale = state.scale
        shapeMask.path = path

        border.frame = root.bounds
        border.contentsScale = state.scale
        border.path = path
        border.isHidden = !state.showBorder

        root.shadowPath = path
        root.isHidden = false

        CATransaction.commit()
    }

    func hide() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.isHidden = true
        content.contents = nil
        CATransaction.commit()
    }

    private static func path(for shape: LensShape, in rect: CGRect, cornerRadius: CGFloat) -> CGPath {
        switch shape {
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .roundedRect:
            return CGPath(roundedRect: rect,
                          cornerWidth: min(cornerRadius, rect.width / 2),
                          cornerHeight: min(cornerRadius, rect.height / 2),
                          transform: nil)
        case .rect:
            return CGPath(rect: rect, transform: nil)
        }
    }
}
