#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

// Render "<=> " icon variants for the Less app (Less equals More)
// Each variant shares the same teal-to-emerald gradient background.
//
// Usage:
//   swift Scripts/render-icon.swift                 # render all variant PNGs + install default as .icns
//   swift Scripts/render-icon.swift variant2         # install a specific variant as the active icon

// ── Background (shared) ─────────────────────────────────────────

func drawBackground(_ ctx: CGContext, size: CGFloat) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22
    let bgPath = CGPath(roundedRect: rect.insetBy(dx: size * 0.02, dy: size * 0.02),
                        cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                        transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.05, green: 0.30, blue: 0.35, alpha: 1.0),
        CGColor(red: 0.10, green: 0.55, blue: 0.45, alpha: 1.0),
    ] as CFArray
    let locations: [CGFloat] = [0.0, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: locations) {
        ctx.drawLinearGradient(gradient,
                              start: CGPoint(x: 0, y: size),
                              end: CGPoint(x: size, y: 0),
                              options: [])
    }
    ctx.resetClip()

    // Subtle inner shadow
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01),
                  blur: size * 0.04,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
    ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.15))
    ctx.setLineWidth(size * 0.005)
    ctx.strokePath()
    ctx.restoreGState()
}

// ── Variant 1: Balanced ─────────────────────────────────────────
// All three glyphs (<, =, >) evenly weighted and spaced.

func renderVariant1(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }

    drawBackground(ctx, size: size)

    let centerY = size * 0.50
    let strokeWidth = size * 0.075
    let armH = size * 0.17       // vertical arm half-height for chevrons
    let eqGap = size * 0.065     // half-gap between the two = bars

    // Horizontal layout: <  =  >
    let leftTip  = size * 0.14
    let leftEnd  = size * 0.34
    let eqLeft   = size * 0.39
    let eqRight  = size * 0.61
    let rightTip = size * 0.86
    let rightEnd = size * 0.66

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.025,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineWidth(strokeWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // < chevron
    let leftChevron = CGMutablePath()
    leftChevron.move(to: CGPoint(x: leftEnd, y: centerY - armH))
    leftChevron.addLine(to: CGPoint(x: leftTip, y: centerY))
    leftChevron.addLine(to: CGPoint(x: leftEnd, y: centerY + armH))
    ctx.addPath(leftChevron)
    ctx.strokePath()

    // = bars
    let eqTop = CGMutablePath()
    eqTop.move(to: CGPoint(x: eqLeft, y: centerY - eqGap))
    eqTop.addLine(to: CGPoint(x: eqRight, y: centerY - eqGap))
    ctx.addPath(eqTop)
    ctx.strokePath()

    let eqBot = CGMutablePath()
    eqBot.move(to: CGPoint(x: eqLeft, y: centerY + eqGap))
    eqBot.addLine(to: CGPoint(x: eqRight, y: centerY + eqGap))
    ctx.addPath(eqBot)
    ctx.strokePath()

    // > chevron
    let rightChevron = CGMutablePath()
    rightChevron.move(to: CGPoint(x: rightEnd, y: centerY - armH))
    rightChevron.addLine(to: CGPoint(x: rightTip, y: centerY))
    rightChevron.addLine(to: CGPoint(x: rightEnd, y: centerY + armH))
    ctx.addPath(rightChevron)
    ctx.strokePath()

    ctx.restoreGState()
    image.unlockFocus()
    return image
}

// ── Variant 2: Bold chevrons, light equals ──────────────────────
// < and > are heavier; the = bars are thinner, creating visual emphasis
// on the "less" and "more" with a quiet link between them.

func renderVariant2(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }

    drawBackground(ctx, size: size)

    let centerY = size * 0.50
    let boldStroke = size * 0.09
    let thinStroke = size * 0.045
    let armH = size * 0.20
    let eqGap = size * 0.07

    let leftTip  = size * 0.13
    let leftEnd  = size * 0.36
    let eqLeft   = size * 0.40
    let eqRight  = size * 0.60
    let rightTip = size * 0.87
    let rightEnd = size * 0.64

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.025,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // < chevron (bold)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineWidth(boldStroke)
    let leftChevron = CGMutablePath()
    leftChevron.move(to: CGPoint(x: leftEnd, y: centerY - armH))
    leftChevron.addLine(to: CGPoint(x: leftTip, y: centerY))
    leftChevron.addLine(to: CGPoint(x: leftEnd, y: centerY + armH))
    ctx.addPath(leftChevron)
    ctx.strokePath()

    // = bars (thin, subtle)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.70))
    ctx.setLineWidth(thinStroke)
    let eqTop = CGMutablePath()
    eqTop.move(to: CGPoint(x: eqLeft, y: centerY - eqGap))
    eqTop.addLine(to: CGPoint(x: eqRight, y: centerY - eqGap))
    ctx.addPath(eqTop)
    ctx.strokePath()
    let eqBot = CGMutablePath()
    eqBot.move(to: CGPoint(x: eqLeft, y: centerY + eqGap))
    eqBot.addLine(to: CGPoint(x: eqRight, y: centerY + eqGap))
    ctx.addPath(eqBot)
    ctx.strokePath()

    // > chevron (bold)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineWidth(boldStroke)
    let rightChevron = CGMutablePath()
    rightChevron.move(to: CGPoint(x: rightEnd, y: centerY - armH))
    rightChevron.addLine(to: CGPoint(x: rightTip, y: centerY))
    rightChevron.addLine(to: CGPoint(x: rightEnd, y: centerY + armH))
    ctx.addPath(rightChevron)
    ctx.strokePath()

    ctx.restoreGState()
    image.unlockFocus()
    return image
}

// ── Variant 3: Connected / ligature style ───────────────────────
// The < = > are drawn as a single connected glyph — the equals bars
// extend directly from the chevron tips, forming one fluid shape.

func renderVariant3(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }

    drawBackground(ctx, size: size)

    let centerY = size * 0.50
    let strokeWidth = size * 0.08
    let armH = size * 0.18
    let eqGap = size * 0.07

    let leftTip  = size * 0.13
    let leftEnd  = size * 0.35
    let rightEnd = size * 0.65
    let rightTip = size * 0.87

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.025,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineWidth(strokeWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Top stroke: right arm of < → top = bar → left arm of >
    let topPath = CGMutablePath()
    topPath.move(to: CGPoint(x: leftEnd, y: centerY - armH))
    topPath.addLine(to: CGPoint(x: leftTip, y: centerY))          // < top arm down to tip
    // We draw top and bottom as separate connected strokes
    ctx.addPath(topPath)
    ctx.strokePath()

    // Top bar connecting < tip area to > tip area
    let topBar = CGMutablePath()
    topBar.move(to: CGPoint(x: leftEnd, y: centerY - eqGap))
    topBar.addLine(to: CGPoint(x: rightEnd, y: centerY - eqGap))
    ctx.addPath(topBar)
    ctx.strokePath()

    // Bottom bar
    let botBar = CGMutablePath()
    botBar.move(to: CGPoint(x: leftEnd, y: centerY + eqGap))
    botBar.addLine(to: CGPoint(x: rightEnd, y: centerY + eqGap))
    ctx.addPath(botBar)
    ctx.strokePath()

    // < bottom arm (from tip back out)
    let leftBot = CGMutablePath()
    leftBot.move(to: CGPoint(x: leftTip, y: centerY))
    leftBot.addLine(to: CGPoint(x: leftEnd, y: centerY + armH))
    ctx.addPath(leftBot)
    ctx.strokePath()

    // > chevron
    let rightChevron = CGMutablePath()
    rightChevron.move(to: CGPoint(x: rightEnd, y: centerY - armH))
    rightChevron.addLine(to: CGPoint(x: rightTip, y: centerY))
    rightChevron.addLine(to: CGPoint(x: rightEnd, y: centerY + armH))
    ctx.addPath(rightChevron)
    ctx.strokePath()

    ctx.restoreGState()
    image.unlockFocus()
    return image
}

// ── Variant 4: Stacked / compact ────────────────────────────────
// The < and > are taller and tighter, with the = bars nestled between
// them. More of a "mathematical operator" feel, compact and punchy.

func renderVariant4(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }

    drawBackground(ctx, size: size)

    let centerY = size * 0.50
    let strokeWidth = size * 0.08
    let armH = size * 0.22       // taller chevrons
    let eqGap = size * 0.065

    // Tighter horizontal layout
    let leftTip  = size * 0.15
    let leftEnd  = size * 0.38
    let eqLeft   = size * 0.38
    let eqRight  = size * 0.62
    let rightTip = size * 0.85
    let rightEnd = size * 0.62

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.025,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineWidth(strokeWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // < chevron
    let leftChevron = CGMutablePath()
    leftChevron.move(to: CGPoint(x: leftEnd, y: centerY - armH))
    leftChevron.addLine(to: CGPoint(x: leftTip, y: centerY))
    leftChevron.addLine(to: CGPoint(x: leftEnd, y: centerY + armH))
    ctx.addPath(leftChevron)
    ctx.strokePath()

    // = bars (tucked between the chevrons)
    let eqTop = CGMutablePath()
    eqTop.move(to: CGPoint(x: eqLeft, y: centerY - eqGap))
    eqTop.addLine(to: CGPoint(x: eqRight, y: centerY - eqGap))
    ctx.addPath(eqTop)
    ctx.strokePath()
    let eqBot = CGMutablePath()
    eqBot.move(to: CGPoint(x: eqLeft, y: centerY + eqGap))
    eqBot.addLine(to: CGPoint(x: eqRight, y: centerY + eqGap))
    ctx.addPath(eqBot)
    ctx.strokePath()

    // > chevron
    let rightChevron = CGMutablePath()
    rightChevron.move(to: CGPoint(x: rightEnd, y: centerY - armH))
    rightChevron.addLine(to: CGPoint(x: rightTip, y: centerY))
    rightChevron.addLine(to: CGPoint(x: rightEnd, y: centerY + armH))
    ctx.addPath(rightChevron)
    ctx.strokePath()

    ctx.restoreGState()
    image.unlockFocus()
    return image
}

// ── Image I/O helpers ───────────────────────────────────────────

func savePNG(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to render PNG")
        return
    }
    try! pngData.write(to: URL(fileURLWithPath: path))
    print("Saved: \(path)")
}

func createICNS(render: (CGFloat) -> NSImage, at path: String) {
    let sizes: [(CGFloat, String)] = [
        (16, "16x16"), (32, "16x16@2x"),
        (32, "32x32"), (64, "32x32@2x"),
        (128, "128x128"), (256, "128x128@2x"),
        (256, "256x256"), (512, "256x256@2x"),
        (512, "512x512"), (1024, "512x512@2x"),
    ]

    let iconsetPath = NSTemporaryDirectory() + "Less.iconset"
    try? FileManager.default.removeItem(atPath: iconsetPath)
    try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

    for (size, name) in sizes {
        let image = render(size)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { continue }
        try! pngData.write(to: URL(fileURLWithPath: iconsetPath + "/icon_\(name).png"))
    }

    // Also save a 1024px PNG for reference
    let bigImage = render(1024)
    let pngPath = (path as NSString).deletingLastPathComponent + "/icon-1024.png"
    savePNG(bigImage, to: pngPath)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetPath, "-o", path]
    try! process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
        print("Created: \(path)")
    } else {
        print("iconutil failed with status \(process.terminationStatus)")
    }
    try? FileManager.default.removeItem(atPath: iconsetPath)
}

// ── Main ────────────────────────────────────────────────────────

let scriptPath = CommandLine.arguments[0]
let projectDir: String
if scriptPath.contains("/Scripts/") {
    projectDir = (scriptPath as NSString).deletingLastPathComponent
                    .replacingOccurrences(of: "/Scripts", with: "")
} else {
    projectDir = FileManager.default.currentDirectoryPath
}
let resourcesDir = projectDir + "/Resources"

let variants: [(String, (CGFloat) -> NSImage)] = [
    ("variant1-balanced", renderVariant1),
    ("variant2-bold-chevrons", renderVariant2),
    ("variant3-connected", renderVariant3),
    ("variant4-compact", renderVariant4),
]

let chosenVariant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil

if let choice = chosenVariant {
    // Install a specific variant as the active icon
    guard let (_, render) = variants.first(where: { $0.0.contains(choice) }) else {
        print("Unknown variant: \(choice)")
        print("Available: \(variants.map { $0.0 }.joined(separator: ", "))")
        exit(1)
    }
    print("Installing \(choice) as active icon...")
    createICNS(render: render, at: resourcesDir + "/AppIcon.icns")
} else {
    // Render all variant previews as 1024px PNGs
    print("Rendering all <=> icon variants...")
    for (name, render) in variants {
        let image = render(1024)
        savePNG(image, to: resourcesDir + "/\(name).png")
    }

    // Default: install variant1 as the active icon
    print("\nInstalling variant1-balanced as active icon...")
    createICNS(render: renderVariant1, at: resourcesDir + "/AppIcon.icns")
}

print("Done!")
