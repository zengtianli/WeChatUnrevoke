import AppKit
import Foundation

// Render only editorial text, separately from the untouched screen recordings.
let spec = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: String]
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 720, pixelsHigh: 840,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: 720, height: 840).fill()
func label(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(calibratedRed: 0.14, green: 0.23, blue: 0.17, alpha: 1),
        .paragraphStyle: paragraph
    ]
    (text as NSString).draw(in: NSRect(x: 22, y: y, width: 676, height: 36), withAttributes: attrs)
}
label(spec["title"]!, y: 784, size: 18, weight: .semibold)
label(spec["line1"]!, y: 77, size: 18, weight: .semibold)
label(spec["line2"]!, y: 39, size: 13, weight: .regular)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
