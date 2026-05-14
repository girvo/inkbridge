#!/usr/bin/env swift
// Generates AppIcon.appiconset for InkBridge.app by rasterising the
// SF Symbol `scribble.variable` onto a rounded indigo square at each
// macOS app-icon size. Run from the inkflow-app/ root:
//
//   swift scripts/gen-icon.swift
//
// Re-run whenever you tweak the colours / symbol below; the script
// rewrites every PNG and Contents.json under the AppIcon.appiconset
// folder.

import AppKit

let iconsetPath = "InkBridge/Resources/Assets.xcassets/AppIcon.appiconset"
let bgColor = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.22, alpha: 1.0)
let fgColor = NSColor.white
let symbolName = "scribble.variable"

func renderIcon(pixels: Int) -> Data {
    let s = CGFloat(pixels)
    let cornerRadius = s * 0.22

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        fatalError("could not allocate bitmap rep at \(pixels)px")
    }
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let bgRect = NSRect(x: 0, y: 0, width: s, height: s)
    bgColor.setFill()
    NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

    let symbolPoint = s * 0.6
    let cfg = NSImage.SymbolConfiguration(pointSize: symbolPoint, weight: .regular)
    if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let symSize = symbol.size
        let drawRect = NSRect(
            x: (s - symSize.width)  / 2,
            y: (s - symSize.height) / 2,
            width:  symSize.width,
            height: symSize.height
        )

        let tinted = NSImage(size: symSize)
        tinted.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: symSize))
        fgColor.set()
        NSRect(origin: .zero, size: symSize).fill(using: .sourceIn)
        tinted.unlockFocus()
        tinted.draw(in: drawRect)
    } else {
        FileHandle.standardError.write("warning: SF Symbol '\(symbolName)' unavailable\n".data(using: .utf8)!)
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed at \(pixels)px")
    }
    return data
}

struct IconSpec {
    let filename: String
    let scale: String
    let size: String
    let pixels: Int
}

let specs: [IconSpec] = [
    IconSpec(filename: "icon_16x16.png",      scale: "1x", size: "16x16",   pixels: 16),
    IconSpec(filename: "icon_16x16@2x.png",   scale: "2x", size: "16x16",   pixels: 32),
    IconSpec(filename: "icon_32x32.png",      scale: "1x", size: "32x32",   pixels: 32),
    IconSpec(filename: "icon_32x32@2x.png",   scale: "2x", size: "32x32",   pixels: 64),
    IconSpec(filename: "icon_128x128.png",    scale: "1x", size: "128x128", pixels: 128),
    IconSpec(filename: "icon_128x128@2x.png", scale: "2x", size: "128x128", pixels: 256),
    IconSpec(filename: "icon_256x256.png",    scale: "1x", size: "256x256", pixels: 256),
    IconSpec(filename: "icon_256x256@2x.png", scale: "2x", size: "256x256", pixels: 512),
    IconSpec(filename: "icon_512x512.png",    scale: "1x", size: "512x512", pixels: 512),
    IconSpec(filename: "icon_512x512@2x.png", scale: "2x", size: "512x512", pixels: 1024),
]

let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for spec in specs {
    let data = renderIcon(pixels: spec.pixels)
    let url = URL(fileURLWithPath: "\(iconsetPath)/\(spec.filename)")
    try data.write(to: url)
    print("wrote \(spec.filename) (\(spec.pixels)px)")
}

let contents: [String: Any] = [
    "images": specs.map { [
        "filename": $0.filename,
        "idiom":    "mac",
        "scale":    $0.scale,
        "size":     $0.size,
    ] },
    "info": [ "author": "xcode", "version": 1 ],
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: "\(iconsetPath)/Contents.json"))
print("wrote Contents.json")
