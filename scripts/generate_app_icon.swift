#!/usr/bin/env swift
//
//  generate_app_icon.swift
//  FormBuddy
//
//  Renders the app icon and the in-app brand mark with AppKit + SF Symbols, so
//  the artwork stays in-repo, diffs cleanly, and can be regenerated on any Mac
//  with Xcode. Run from the repo root:
//
//      swift scripts/generate_app_icon.swift
//
//  Writes:
//      FormBuddy/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
//      FormBuddy/Assets.xcassets/BrandMark.imageset/brand-mark.png
//

import AppKit

// MARK: - Brand palette

/// Indigo → violet diagonal, matching AccentColor in the asset catalog.
let brandTop = NSColor(srgbRed: 0.38, green: 0.45, blue: 0.98, alpha: 1)
let brandBottom = NSColor(srgbRed: 0.55, green: 0.30, blue: 0.94, alpha: 1)
let accentColor = NSColor(srgbRed: 0.31, green: 0.42, blue: 0.93, alpha: 1)

// MARK: - Drawing helpers

func drawGradient(in rect: NSRect) {
    let gradient = NSGradient(starting: brandTop, ending: brandBottom)
    gradient?.draw(in: rect, angle: -45)
}

/// A soft light from the top-left so the icon doesn't read as flat.
func drawHighlight(in rect: NSRect) {
    let highlight = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.24),
        NSColor.white.withAlphaComponent(0.0),
    ])
    highlight?.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height * 0.6),
                    relativeCenterPosition: NSPoint(x: -0.4, y: 0.9))
}

func symbol(named name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    return base.withSymbolConfiguration(config)
}

/// Redraws an SF Symbol in a single solid color (symbols render as template art).
func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size, flipped: false) { rect in
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    return out
}

/// Draws `image` centered in `rect`, scaled to fit while preserving aspect.
func drawCentered(_ image: NSImage, in rect: NSRect, padding: CGFloat = 0) {
    let box = rect.insetBy(dx: padding, dy: padding)
    guard box.width > 0, box.height > 0, image.size.width > 0, image.size.height > 0 else { return }
    let scale = min(box.width / image.size.width, box.height / image.size.height)
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    let origin = NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2)
    image.draw(in: NSRect(origin: origin, size: size))
}

func pngData(size: NSSize, opaque: Bool = false, draw: (NSRect) -> Void) -> Data? {
    let pixelsWide = Int(size.width)
    let pixelsHigh = Int(size.height)
    // Draw into an alpha-capable bitmap first: NSGraphicsContext requires alpha.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelsWide,
        pixelsHigh: pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: pixelsWide * 4,
        bitsPerPixel: 32
    ) else { return nil }
    rep.size = size

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw(NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()

    guard let drawn = rep.cgImage else { return nil }
    // Re-render through a colour type that matches the intent: `noneSkipLast`
    // encodes an RGB PNG with no alpha channel (required for the App Store icon).
    let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    let bounds = CGRect(x: 0, y: 0, width: drawn.width, height: drawn.height)
    guard let output = CGContext(
        data: nil,
        width: drawn.width,
        height: drawn.height,
        bitsPerComponent: 8,
        bytesPerRow: drawn.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: alphaInfo.rawValue
    ) else { return nil }
    if opaque {
        output.setFillColor(NSColor.white.cgColor)
        output.fill(bounds)
    }
    output.draw(drawn, in: bounds)
    guard let final = output.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: final).representation(using: .png, properties: [:])
}

func write(_ data: Data?, to path: String) {
    guard let data else {
        FileHandle.standardError.write(Data("failed to render \(path)\n".utf8))
        exit(1)
    }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    do {
        try data.write(to: url)
        print("wrote \(path) (\(data.count) bytes)")
    } catch {
        FileHandle.standardError.write(Data("failed to write \(path): \(error)\n".utf8))
        exit(1)
    }
}

// MARK: - App icon

/// Full-bleed 1024² icon (iOS applies the rounded mask). No transparency, no
/// pre-rounded corners.
func renderAppIcon() -> Data? {
    let size = NSSize(width: 1024, height: 1024)
    return pngData(size: size, opaque: true) { rect in
        drawGradient(in: rect)
        drawHighlight(in: rect)

        // A faint ring echoes the knee-angle instrumentation.
        let ringRect = rect.insetBy(dx: 176, dy: 176)
        let ring = NSBezierPath(ovalIn: ringRect)
        ring.lineWidth = 10
        NSColor.white.withAlphaComponent(0.16).setStroke()
        ring.stroke()

        guard let figure = symbol(named: "figure.strengthtraining.traditional",
                                  pointSize: 600, weight: .semibold) else { return }
        let white = tinted(figure, .white)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 36
        shadow.shadowOffset = NSSize(width: 0, height: -14)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        drawCentered(white, in: rect, padding: 210)
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - In-app brand mark

/// Transparent glyph in the brand accent, for empty states and the About row.
func renderBrandMark() -> Data? {
    let size = NSSize(width: 512, height: 512)
    return pngData(size: size) { rect in
        guard let figure = symbol(named: "figure.strengthtraining.traditional",
                                  pointSize: 420, weight: .semibold) else { return }
        drawCentered(tinted(figure, accentColor), in: rect, padding: 48)
    }
}

// MARK: - Entry point

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("FormBuddy/Assets.xcassets")

write(renderAppIcon(),
      to: assets.appendingPathComponent("AppIcon.appiconset/AppIcon-1024.png").path)
write(renderBrandMark(),
      to: assets.appendingPathComponent("BrandMark.imageset/brand-mark.png").path)
