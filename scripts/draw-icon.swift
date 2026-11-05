import AppKit

// Same canvas, geometry and palette as ModelDeck's native icon, with a voice waveform.
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let pixels = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let side = CGFloat(pixels)
NSColor(calibratedRed: 0.055, green: 0.085, blue: 0.09, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: side * 0.06, y: side * 0.06, width: side * 0.88, height: side * 0.88),
             xRadius: side * 0.19, yRadius: side * 0.19).fill()
NSColor(calibratedRed: 0.40, green: 0.88, blue: 0.72, alpha: 1).setStroke()
for (index, height) in [0.13, 0.27, 0.42, 0.27, 0.13].enumerated() {
    let x = side * (0.27 + Double(index) * 0.115)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x, y: side * (0.56 - height / 2)))
    path.line(to: NSPoint(x: x, y: side * (0.56 + height / 2)))
    path.lineWidth = side * 0.045; path.lineCapStyle = .round; path.stroke()
}
let deck = NSBezierPath()
deck.move(to: NSPoint(x: side * 0.25, y: side * 0.31))
deck.line(to: NSPoint(x: side * 0.50, y: side * 0.20))
deck.line(to: NSPoint(x: side * 0.75, y: side * 0.31))
deck.lineWidth = side * 0.035; deck.lineCapStyle = .round; deck.lineJoinStyle = .round; deck.stroke()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
