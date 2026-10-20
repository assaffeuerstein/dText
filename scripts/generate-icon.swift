// Rebuild the original, code-drawn dText icon: swift scripts/generate-icon.swift
import AppKit
import Foundation

let destination = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appending(path: "dText/Assets.xcassets/AppIcon.appiconset")
var entries: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let box = NSBezierPath(roundedRect: NSRect(x: 92, y: 92, width: 840, height: 840), xRadius: 188, yRadius: 188)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowBlurRadius = 35
        shadow.shadowOffset = NSSize(width: 0, height: -18)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor(red: 0.12, green: 0.43, blue: 0.34, alpha: 1).setFill()
        box.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(red: 0.22, green: 0.63, blue: 0.50, alpha: 1),
                   ending: NSColor(red: 0.12, green: 0.43, blue: 0.35, alpha: 1))!.draw(in: box, angle: -75)
        let font = NSFont.systemFont(ofSize: 730, weight: .semibold)
        let rounded = NSFont(descriptor: font.fontDescriptor.withDesign(.rounded)!, size: 730)!
        ("d" as NSString).draw(at: NSPoint(x: 238, y: 109), withAttributes: [
            .font: rounded, .foregroundColor: NSColor.white.withAlphaComponent(0.96)
        ])
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: NSRect(x: 734, y: 303, width: 17, height: 356), xRadius: 8, yRadius: 8).fill()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon-\(points)@\(scale)x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: destination.appending(path: filename))
        entries.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
    }
}
let json: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    .write(to: destination.appending(path: "Contents.json"))
