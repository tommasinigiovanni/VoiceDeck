import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: representation)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let p = CGFloat(pixels)
        guard CommandLine.arguments.count > 3,
              let source = NSImage(contentsOfFile: CommandLine.arguments[3]) else {
            fatalError("Specify the source PNG after the iconset and ICNS output paths")
        }
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: p, height: p), from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        let data = representation.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: destination.appendingPathComponent(name))
    }
}

// Package the standard PNG representations directly. This avoids iconutil's
// dependency on an image-conversion service during restricted builds.
if CommandLine.arguments.count > 2 {
    let entries = [("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
                   ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
                   ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
                   ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
                   ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")]
    var chunks = Data()
    for (type, file) in entries {
        let png = try Data(contentsOf: destination.appendingPathComponent(file))
        chunks.append(Data(type.utf8))
        var size = UInt32(png.count + 8).bigEndian
        withUnsafeBytes(of: &size) { chunks.append(contentsOf: $0) }
        chunks.append(png)
    }
    var icon = Data("icns".utf8)
    var size = UInt32(chunks.count + 8).bigEndian
    withUnsafeBytes(of: &size) { icon.append(contentsOf: $0) }
    icon.append(chunks)
    try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
