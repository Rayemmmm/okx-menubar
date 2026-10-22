import AppKit

let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    NSColor(calibratedRed: 0.075, green: 0.085, blue: 0.10, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 195, yRadius: 195).fill()
    NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
    let border = NSBezierPath(roundedRect: NSRect(x: 67, y: 67, width: 890, height: 890), xRadius: 192, yRadius: 192)
    border.lineWidth = 5; border.stroke()
    let text: NSString = "OKX"
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 238, weight: .heavy), .foregroundColor: NSColor.white]
    let textSize = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: (1024-textSize.width)/2, y: 440), withAttributes: attributes)
    let mint = NSColor(calibratedRed: 0.34, green: 0.94, blue: 0.72, alpha: 1)
    mint.setStroke()
    let line = NSBezierPath(); line.lineWidth = 32; line.lineCapStyle = .round; line.lineJoinStyle = .round
    line.move(to: NSPoint(x: 258, y: 330)); line.line(to: NSPoint(x: 380, y: 390))
    line.line(to: NSPoint(x: 491, y: 332)); line.line(to: NSPoint(x: 627, y: 411)); line.line(to: NSPoint(x: 766, y: 411)); line.stroke()
    let caption: NSString = "READ ONLY"
    let captionAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 48, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1)]
    let captionSize = caption.size(withAttributes: captionAttributes)
    caption.draw(at: NSPoint(x: (1024-captionSize.width)/2, y: 222), withAttributes: captionAttributes)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory + "/\(size).png"))
}
