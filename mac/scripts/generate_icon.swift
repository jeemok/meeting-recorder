#!/usr/bin/env swift
//
// Render the Meeting Recorder app icon to every size required by an
// AppIcon.iconset. Re-run whenever the design changes:
//
//   swift scripts/generate_icon.swift
//
// Output: Resources/AppIcon.iconset/*.png
//
// The bundle's .icns is then produced by:
//   iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
// (build.sh does this automatically.)

import AppKit
import CoreGraphics
import Foundation

// MARK: - Design

/// Draws the icon at an arbitrary pixel size. Keep proportions size-
/// independent so the small sizes (16, 32) still look like the big ones.
func drawIcon(pixels: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    let bounds = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    let cornerRadius = pixels * 0.225  // macOS-style squircle

    // Clip the canvas to the squircle so the gradient + shadows stay inside.
    let clip = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(clip)
    ctx.clip()

    // --- Background gradient: warm crimson, recording-app vibe ----------
    let topColor = NSColor(srgbRed: 1.00, green: 0.42, blue: 0.42, alpha: 1.0).cgColor      // #FF6B6B
    let bottomColor = NSColor(srgbRed: 0.55, green: 0.08, blue: 0.22, alpha: 1.0).cgColor   // #8B1538
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [topColor, bottomColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: pixels),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    // --- Soft top highlight for a glassy finish -------------------------
    let highlight = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(white: 1.0, alpha: 0.18).cgColor,
            NSColor(white: 1.0, alpha: 0.0).cgColor
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        highlight,
        start: CGPoint(x: 0, y: pixels),
        end: CGPoint(x: 0, y: pixels * 0.55),
        options: []
    )

    // --- Waveform bars ---------------------------------------------------
    // Five vertical pills of varying heights, centered. Drop-shadow for depth.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -pixels * 0.012),
        blur: pixels * 0.04,
        color: NSColor(white: 0, alpha: 0.25).cgColor
    )

    let heightFactors: [CGFloat] = [0.30, 0.55, 0.78, 0.55, 0.30]
    let barCount = heightFactors.count
    let barWidth = pixels * 0.095
    let barGap = pixels * 0.06
    let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
    let startX = (pixels - totalWidth) / 2
    let centerY = pixels / 2

    NSColor.white.setFill()
    for i in 0..<barCount {
        let h = pixels * heightFactors[i]
        let x = startX + CGFloat(i) * (barWidth + barGap)
        let y = centerY - h / 2
        let rect = CGRect(x: x, y: y, width: barWidth, height: h)
        let pill = CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
        ctx.addPath(pill)
        ctx.fillPath()
    }
    ctx.restoreGState()

    // --- Tiny "REC" dot in the top-right corner -------------------------
    let dotDiameter = pixels * 0.075
    let dotPadding = pixels * 0.11
    let dotRect = CGRect(
        x: pixels - dotPadding - dotDiameter,
        y: pixels - dotPadding - dotDiameter,
        width: dotDiameter,
        height: dotDiameter
    )
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: pixels * 0.025,
        color: NSColor(srgbRed: 1, green: 0.9, blue: 0.9, alpha: 0.9).cgColor
    )
    NSColor.white.setFill()
    ctx.fillEllipse(in: dotRect)
    ctx.restoreGState()

    return image
}

// MARK: - Encode

func writePNG(_ image: NSImage, to url: URL, pixels: CGFloat) throws {
    guard let rep = image.bestRepresentation(for: NSRect(x: 0, y: 0, width: pixels, height: pixels), context: nil, hints: nil),
          let bitmap = rep as? NSBitmapImageRep ?? NSBitmapImageRep(data: image.tiffRepresentation ?? Data()),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    try png.write(to: url)
}

// MARK: - Driver

let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = here.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// Standard macOS iconset sizes: name → pixel dimensions.
let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for entry in sizes {
    let img = drawIcon(pixels: entry.px)
    let out = iconset.appendingPathComponent(entry.name)
    try writePNG(img, to: out, pixels: entry.px)
    print("✓ \(entry.name) (\(Int(entry.px))px)")
}

print("\nNext: iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns")
