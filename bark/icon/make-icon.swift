// Draws the Yumu app icon: the end grain of a log (原木) on a rounded square.
// Usage: swift bark/icon/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else { return image }
    let unit = size / 1024
    let inset = 100 * unit
    let square = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let path = CGPath(roundedRect: square, cornerWidth: 190 * unit, cornerHeight: 190 * unit, transform: nil)
    context.addPath(path)
    context.clip()
    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(red: 0.40, green: 0.26, blue: 0.15, alpha: 1),
        CGColor(red: 0.27, green: 0.16, blue: 0.09, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

    // Log end: a warm disc with rings, slightly off-centre like a real cut.
    let centre = CGPoint(x: size * 0.5, y: size * 0.5)
    let radius = size * 0.33
    context.setFillColor(CGColor(red: 0.93, green: 0.80, blue: 0.60, alpha: 1))
    context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
    context.setStrokeColor(CGColor(red: 0.62, green: 0.43, blue: 0.26, alpha: 0.9))
    let rings: [CGFloat] = [0.18, 0.34, 0.52, 0.70, 0.88]
    for (index, fraction) in rings.enumerated() {
        let r = radius * fraction
        let wobble = CGPoint(x: centre.x + CGFloat(index % 2 == 0 ? 6 : -4) * unit, y: centre.y - CGFloat(index) * 3 * unit)
        context.setLineWidth((index == rings.count - 1 ? 14 : 9) * unit)
        context.strokeEllipse(in: CGRect(x: wobble.x - r, y: wobble.y - r, width: 2 * r, height: 2 * r))
    }
    // A single crack, the mark of real wood.
    context.setLineWidth(10 * unit)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: centre.x + radius * 0.2, y: centre.y + radius * 0.1))
    context.addLine(to: CGPoint(x: centre.x + radius * 0.92, y: centre.y + radius * 0.38))
    context.strokePath()
    image.unlockFocus()
    return image
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = CGFloat(size * scale)
        let image = draw(size: pixels)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { continue }
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try? png.write(to: output.appendingPathComponent(name))
    }
}
