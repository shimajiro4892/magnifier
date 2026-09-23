// Generates the app icon (Assets.xcassets/AppIcon.appiconset) with Core Graphics.
//
//   swift Tools/make-app-icon.swift
//
// The icon is drawn at every required size as vector art, so the small sizes
// stay crisp. Run this again after tweaking the design.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Design

/// Everything is laid out on a 1024x1024 canvas, with Apple's macOS icon grid
/// (the rounded square occupies the inner 824x824).
let canvasSize: CGFloat = 1024
let squircleInset: CGFloat = 100
let squircleRect = CGRect(x: squircleInset,
                          y: squircleInset,
                          width: canvasSize - squircleInset * 2,
                          height: canvasSize - squircleInset * 2)
let squircleRadius: CGFloat = squircleRect.width * 0.2237

// Magnifier glyph, in top-left coordinates.
let lensCenter = CGPoint(x: 465, y: 465)
let lensRadius: CGFloat = 180
let glyphStroke: CGFloat = 70
let handleStroke: CGFloat = 62
let handleStart = CGPoint(x: lensCenter.x + lensRadius * 0.7071, y: lensCenter.y + lensRadius * 0.7071)
let handleEnd = CGPoint(x: 743, y: 743)

let topColor = CGColor(srgbRed: 0.44, green: 0.70, blue: 1.00, alpha: 1)
let bottomColor = CGColor(srgbRed: 0.13, green: 0.33, blue: 0.80, alpha: 1)

/// Converts a top-left origin point into Core Graphics (bottom-left) space.
func cgPoint(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.x, y: canvasSize - point.y)
}

// MARK: - Drawing

func drawIcon(in context: CGContext) {
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let squircle = CGPath(roundedRect: squircleRect,
                          cornerWidth: squircleRadius,
                          cornerHeight: squircleRadius,
                          transform: nil)

    // Soft shadow under the rounded square.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14),
                      blur: 30,
                      color: NSColor.black.withAlphaComponent(0.30).cgColor)
    context.addPath(squircle)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    // Background gradient.
    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [topColor, bottomColor] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: squircleRect.minX, y: squircleRect.maxY),
                               end: CGPoint(x: squircleRect.maxX, y: squircleRect.minY),
                               options: [])
    // Subtle sheen: a smooth highlight fading out towards the middle.
    let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [NSColor.white.withAlphaComponent(0.14).cgColor,
                                    NSColor.white.withAlphaComponent(0.0).cgColor] as CFArray,
                           locations: [0, 1])!
    context.drawLinearGradient(sheen,
                               start: CGPoint(x: squircleRect.minX, y: squircleRect.maxY),
                               end: CGPoint(x: squircleRect.minX, y: squircleRect.midY),
                               options: [])
    context.restoreGState()

    // Handle (drawn first so the ring overlaps it cleanly).
    context.saveGState()
    context.setLineCap(.round)
    context.setLineWidth(handleStroke)
    context.setStrokeColor(NSColor.white.cgColor)
    context.move(to: cgPoint(handleStart))
    context.addLine(to: cgPoint(handleEnd))
    context.strokePath()
    context.restoreGState()

    // Lens.
    let lensRect = CGRect(x: lensCenter.x - lensRadius,
                          y: lensCenter.y - lensRadius,
                          width: lensRadius * 2,
                          height: lensRadius * 2)
    context.saveGState()
    context.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    context.fillEllipse(in: CGRect(x: lensRect.minX,
                                   y: canvasSize - lensRect.maxY,
                                   width: lensRect.width,
                                   height: lensRect.height))
    context.setLineWidth(glyphStroke)
    context.setStrokeColor(NSColor.white.cgColor)
    context.strokeEllipse(in: CGRect(x: lensRect.minX,
                                     y: canvasSize - lensRect.maxY,
                                     width: lensRect.width,
                                     height: lensRect.height))
    context.restoreGState()
}

func renderIcon(size: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil,
                                  width: size,
                                  height: size,
                                  bitsPerComponent: 8,
                                  bytesPerRow: size * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("could not create context")
    }
    let scale = CGFloat(size) / canvasSize
    context.scaleBy(x: scale, y: scale)
    drawIcon(in: context)
    guard let image = context.makeImage() else { fatalError("could not render") }
    return image
}

// MARK: - Output

let scriptDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let outputDirectory = scriptDirectory
    .deletingLastPathComponent()
    .appendingPathComponent("Magnifier/Assets.xcassets/AppIcon.appiconset")

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("could not create \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("could not write \(url.path)")
    }
    print("wrote \(url.lastPathComponent)")
}

// size -> file names (macOS icon set)
let files: [(pixels: Int, names: [String])] = [
    (16, ["icon_16x16.png"]),
    (32, ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64, ["icon_32x32@2x.png"]),
    (128, ["icon_128x128.png"]),
    (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024, ["icon_512x512@2x.png"]),
]

for (pixels, names) in files {
    let image = renderIcon(size: pixels)
    for name in names {
        write(image, to: outputDirectory.appendingPathComponent(name))
    }
}

// A 512px preview for quick inspection (kept outside the icon set so the asset
// catalog has no unassigned children).
let previewURL = outputDirectory
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Tools/icon-preview.png")
write(renderIcon(size: 512), to: previewURL)
print("done")
