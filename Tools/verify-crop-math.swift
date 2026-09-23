// Verifies the coordinate conventions used by the magnifier lens.
//
//   swift Tools/verify-crop-math.swift
//
// Builds a synthetic 4-quadrant "screen" image (red | green on top,
// blue | yellow at the bottom), crops it exactly like the app does and renders
// the layer tree offscreen to check that the magnified content is upright and
// that the crop follows the cursor.
//
// Two independent render paths are used (CALayer.render(in:) and AppKit's
// cacheDisplay) so the result does not depend on a single implementation detail.

import AppKit
import CoreGraphics
import QuartzCore

let imageWidth = 400
let imageHeight = 300
let lensSize = CGSize(width: 100, height: 100)

func makeTestImage() -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil,
                                  width: imageWidth,
                                  height: imageHeight,
                                  bitsPerComponent: 8,
                                  bytesPerRow: imageWidth * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("no context")
    }

    // CGContext origin is bottom-left.
    func fill(_ rect: CGRect, _ color: CGColor) {
        context.setFillColor(color)
        context.fill(rect)
    }
    fill(CGRect(x: 0, y: imageHeight / 2, width: imageWidth / 2, height: imageHeight / 2), NSColor.red.cgColor)
    fill(CGRect(x: imageWidth / 2, y: imageHeight / 2, width: imageWidth / 2, height: imageHeight / 2), NSColor.green.cgColor)
    fill(CGRect(x: 0, y: 0, width: imageWidth / 2, height: imageHeight / 2), NSColor.blue.cgColor)
    fill(CGRect(x: imageWidth / 2, y: 0, width: imageWidth / 2, height: imageHeight / 2), NSColor.yellow.cgColor)

    return context.makeImage()!
}

/// Reads a pixel out of a bitmap whose first row is the top row.
func color(from buffer: UnsafeMutablePointer<UInt8>, size: CGSize, point: CGPoint) -> NSColor {
    let width = Int(size.width)
    let offset = (Int(point.y) * width + Int(point.x)) * 4
    return NSColor(srgbRed: CGFloat(buffer[offset]) / 255.0,
                   green: CGFloat(buffer[offset + 1]) / 255.0,
                   blue: CGFloat(buffer[offset + 2]) / 255.0,
                   alpha: CGFloat(buffer[offset + 3]) / 255.0)
}

/// Renders a layer tree offscreen. `point` is in the layer's own coordinate
/// system (origin bottom-left, as in a non flipped NSView).
func sampleLayer(_ layer: CALayer, at point: CGPoint) -> NSColor {
    let width = Int(lensSize.width)
    let height = Int(lensSize.height)
    guard let context = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("no context")
    }
    layer.render(in: context)
    guard let data = context.data else { fatalError("no data") }
    // The context's origin is bottom-left while the buffer's first row is the top one.
    let flipped = CGPoint(x: point.x, y: CGFloat(height) - 1 - point.y)
    return color(from: data.bindMemory(to: UInt8.self, capacity: width * height * 4), size: lensSize, point: flipped)
}

/// Renders a view hierarchy through AppKit (second, independent render path).
func sampleView(_ view: NSView, at point: CGPoint) -> NSColor {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("no rep") }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.bitmapData else { fatalError("no data") }
    let width = rep.pixelsWide
    let height = rep.pixelsHigh
    let scaleX = CGFloat(width) / view.bounds.width
    let scaleY = CGFloat(height) / view.bounds.height
    // NSBitmapImageRep rows start at the top.
    let flipped = CGPoint(x: point.x * scaleX, y: (view.bounds.height - point.y) * scaleY - 1)
    return color(from: data, size: CGSize(width: width, height: height), point: flipped)
}

func describe(_ color: NSColor) -> String {
    let r = Int(color.redComponent * 255)
    let g = Int(color.greenComponent * 255)
    let b = Int(color.blueComponent * 255)
    switch (r > 128, g > 128, b > 128) {
    case (true, false, false): return "red (top-left)"
    case (false, true, false): return "green (top-right)"
    case (false, false, true): return "blue (bottom-left)"
    case (true, true, false): return "yellow (bottom-right)"
    default: return "unknown (\(r),\(g),\(b))"
    }
}

// MARK: - The app's math

/// Crop rectangle in normalized display coordinates, origin at the top-left of
/// the display (0 = top, 1 = bottom), as computed from the cursor position.
func cropRect(normalizedX: CGFloat, normalizedY: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
    var x = normalizedX - width / 2
    var y = normalizedY - height / 2
    x = min(max(x, 0), max(0, 1 - width))
    y = min(max(y, 0), max(0, 1 - height))
    return CGRect(x: x, y: y, width: width, height: height)
}

/// Conversion applied by `LensRenderer`: the layer's coordinate system is
/// bottom-left oriented, so the vertical origin of `contentsRect` is mirrored.
func contentsRect(fromTopLeft crop: CGRect) -> CGRect {
    CGRect(x: crop.minX, y: 1 - crop.maxY, width: crop.width, height: crop.height)
}

let image = makeTestImage()
var failures = 0

func check(_ label: String, actual: String, expected: String) {
    let ok = actual == expected
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(label): expected \(expected), got \(actual)")
}

func makeLayers() -> (root: CALayer, content: CALayer) {
    let content = CALayer()
    content.contents = image
    content.contentsGravity = .resize
    content.frame = CGRect(origin: .zero, size: lensSize)
    let root = CALayer()
    root.frame = CGRect(origin: .zero, size: lensSize)
    root.addSublayer(content)
    return (root, content)
}

// MARK: - 1. Contents are drawn upright

do {
    let (root, content) = makeLayers()
    print("plain CALayer: geometryFlipped=\(root.isGeometryFlipped) contentsAreFlipped=\(content.contentsAreFlipped())")

    content.contentsRect = contentsRect(fromTopLeft: CGRect(x: 0, y: 0, width: 1, height: 1))
    check("full image, lens top-left is the display's top-left",
          actual: describe(sampleLayer(root, at: CGPoint(x: 25, y: 75))),
          expected: "red (top-left)")
    check("full image, lens top-right is the display's top-right",
          actual: describe(sampleLayer(root, at: CGPoint(x: 75, y: 75))),
          expected: "green (top-right)")
    check("full image, lens bottom-left is the display's bottom-left",
          actual: describe(sampleLayer(root, at: CGPoint(x: 25, y: 25))),
          expected: "blue (bottom-left)")
    check("full image, lens bottom-right is the display's bottom-right",
          actual: describe(sampleLayer(root, at: CGPoint(x: 75, y: 25))),
          expected: "yellow (bottom-right)")
}

// MARK: - 2. contentsRect origin (plain layer and NSView backed layer)

do {
    let (root, content) = makeLayers()
    let host = NSView(frame: CGRect(origin: .zero, size: lensSize))
    host.wantsLayer = true
    let (viewRoot, viewContent) = makeLayers()
    host.layer!.addSublayer(viewRoot)
    print("view backed: view.isFlipped=\(host.isFlipped) hostLayer.geometryFlipped=\(host.layer!.isGeometryFlipped)")

    // Top band of the display (top 25%) must be red | green.
    let topBand = contentsRect(fromTopLeft: CGRect(x: 0, y: 0, width: 1, height: 0.25))
    content.contentsRect = topBand
    viewContent.contentsRect = topBand
    check("plain layer, top band is red",
          actual: describe(sampleLayer(root, at: CGPoint(x: 25, y: 50))),
          expected: "red (top-left)")
    check("view layer, top band is red",
          actual: describe(sampleLayer(viewRoot, at: CGPoint(x: 25, y: 50))),
          expected: "red (top-left)")
    check("cacheDisplay, top band is red",
          actual: describe(sampleView(host, at: CGPoint(x: 25, y: 50))),
          expected: "red (top-left)")

    // Bottom band of the display (bottom 25%) must be blue | yellow.
    let bottomBand = contentsRect(fromTopLeft: CGRect(x: 0, y: 0.75, width: 1, height: 0.25))
    content.contentsRect = bottomBand
    viewContent.contentsRect = bottomBand
    check("plain layer, bottom band is blue",
          actual: describe(sampleLayer(root, at: CGPoint(x: 25, y: 50))),
          expected: "blue (bottom-left)")
    check("cacheDisplay, bottom band is blue",
          actual: describe(sampleView(host, at: CGPoint(x: 25, y: 50))),
          expected: "blue (bottom-left)")
}

// MARK: - 3. Crop follows the cursor

do {
    let (root, content) = makeLayers()

    // Cursor in the top-left corner: the crop is clamped to the top-left quadrant.
    content.contentsRect = contentsRect(fromTopLeft: cropRect(normalizedX: 0.1, normalizedY: 0.1, width: 0.5, height: 0.5))
    check("cursor top-left -> whole lens red",
          actual: describe(sampleLayer(root, at: CGPoint(x: 50, y: 50))),
          expected: "red (top-left)")

    // Cursor in the bottom-right corner.
    content.contentsRect = contentsRect(fromTopLeft: cropRect(normalizedX: 0.9, normalizedY: 0.9, width: 0.5, height: 0.5))
    check("cursor bottom-right -> whole lens yellow",
          actual: describe(sampleLayer(root, at: CGPoint(x: 50, y: 50))),
          expected: "yellow (bottom-right)")

    // Cursor above the center of the display: the magnified cursor area (upper
    // part of the lens) must show the upper part of the display.
    content.contentsRect = contentsRect(fromTopLeft: cropRect(normalizedX: 0.25, normalizedY: 0.3, width: 0.4, height: 0.4))
    check("cursor above center -> upper lens shows the top of the display",
          actual: describe(sampleLayer(root, at: CGPoint(x: 50, y: 80))),
          expected: "red (top-left)")

    // Cursor below the center of the display.
    content.contentsRect = contentsRect(fromTopLeft: cropRect(normalizedX: 0.25, normalizedY: 0.8, width: 0.4, height: 0.4))
    check("cursor below center -> lower lens shows the bottom of the display",
          actual: describe(sampleLayer(root, at: CGPoint(x: 50, y: 20))),
          expected: "blue (bottom-left)")
}

// MARK: - 4. IOSurface backed contents (exactly what ScreenCaptureKit hands over)

do {
    // ScreenCaptureKit delivers CVPixelBuffers backed by IOSurfaces; simulate one.
    var pixelBuffer: CVPixelBuffer?
    let attributes: [String: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ]
    let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                     imageWidth,
                                     imageHeight,
                                     kCVPixelFormatType_32BGRA,
                                     attributes as CFDictionary,
                                     &pixelBuffer)
    guard status == kCVReturnSuccess, let pixelBuffer else {
        fatalError("could not create pixel buffer: \(status)")
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer),
          let context = CGContext(data: base,
                                  width: imageWidth,
                                  height: imageHeight,
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
        fatalError("could not draw into pixel buffer")
    }
    // CGContext origin is bottom-left, the buffer's first row is the top one.
    context.setFillColor(NSColor.red.cgColor)
    context.fill(CGRect(x: 0, y: imageHeight / 2, width: imageWidth / 2, height: imageHeight / 2))
    context.setFillColor(NSColor.green.cgColor)
    context.fill(CGRect(x: imageWidth / 2, y: imageHeight / 2, width: imageWidth / 2, height: imageHeight / 2))
    context.setFillColor(NSColor.blue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: imageWidth / 2, height: imageHeight / 2))
    context.setFillColor(NSColor.yellow.cgColor)
    context.fill(CGRect(x: imageWidth / 2, y: 0, width: imageWidth / 2, height: imageHeight / 2))

    guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
        fatalError("pixel buffer has no IOSurface")
    }

    let content = CALayer()
    content.contents = surface
    content.contentsGravity = .resize
    content.frame = CGRect(origin: .zero, size: lensSize)
    let root = CALayer()
    root.frame = CGRect(origin: .zero, size: lensSize)
    root.addSublayer(content)

    content.contentsRect = contentsRect(fromTopLeft: CGRect(x: 0, y: 0, width: 1, height: 1))
    check("IOSurface contents, full image top-left",
          actual: describe(sampleLayer(root, at: CGPoint(x: 25, y: 75))),
          expected: "red (top-left)")
    check("IOSurface contents, full image bottom-right",
          actual: describe(sampleLayer(root, at: CGPoint(x: 75, y: 25))),
          expected: "yellow (bottom-right)")

    content.contentsRect = contentsRect(fromTopLeft: cropRect(normalizedX: 0.1, normalizedY: 0.1, width: 0.5, height: 0.5))
    check("IOSurface contents, cursor top-left -> whole lens red",
          actual: describe(sampleLayer(root, at: CGPoint(x: 50, y: 50))),
          expected: "red (top-left)")

    content.contentsRect = contentsRect(fromTopLeft: cropRect(normalizedX: 0.25, normalizedY: 0.8, width: 0.4, height: 0.4))
    check("IOSurface contents, cursor below center -> lower lens shows the bottom",
          actual: describe(sampleLayer(root, at: CGPoint(x: 50, y: 20))),
          expected: "blue (bottom-left)")
}

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
