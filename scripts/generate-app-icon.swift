// Draws the Takt app icon and writes the asset catalog icon set and the README logo.
// Usage: swift scripts/generate-app-icon.swift
//
// Two white tracks with gaps on a teal squircle: parallel timers, pauses are the gaps
// between segments. Laid out on the macOS icon grid (824 pt body on a 1024 pt canvas).
import AppKit

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconSet = root.appending(path: "App/Resources/Assets.xcassets/AppIcon.appiconset")
let logo = root.appending(path: "docs/assets/logo.png")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: stops.map(\.1) as CFArray,
        locations: stops.map(\.0)
    )!
}

func render(pixels: Int) -> Data {
    let scale = CGFloat(pixels) / 1024
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Top-left origin in 1024 pt units. Shadow offsets and blur stay in device pixels.
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)

    let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = CGPath(roundedRect: bodyRect, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Body with drop shadow.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale, color: color(0x000000, 0.28))
    context.addPath(body)
    context.setFillColor(color(0x0F8D80))
    context.fillPath()
    context.restoreGState()

    // Vertical gradient, light at the top.
    context.saveGState()
    context.addPath(body)
    context.clip()
    context.drawLinearGradient(
        gradient([(0, color(0x2BC7B1)), (0.55, color(0x0F8D80)), (1, color(0x07514B))]),
        start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: []
    )
    context.restoreGState()

    // Light rim that fades out towards the bottom.
    context.saveGState()
    context.addPath(CGPath(roundedRect: bodyRect.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
    context.setLineWidth(4)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        gradient([(0, color(0xFFFFFF, 0.45)), (0.35, color(0xFFFFFF, 0.08)), (1, color(0xFFFFFF, 0))]),
        start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: []
    )
    context.restoreGState()

    // Glyph with a soft shadow.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 36 * scale, color: color(0x032B27, 0.40))
    context.setStrokeColor(color(0xFFFFFF))
    context.setLineWidth(96)
    context.setLineCap(.round)
    let segments: [(CGFloat, CGFloat, CGFloat)] = [(317, 549, 416), (667, 707, 416), (317, 420, 608), (538, 707, 608)]
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    for (from, to, y) in segments {
        context.move(to: CGPoint(x: from, y: y))
        context.addLine(to: CGPoint(x: to, y: y))
    }
    context.strokePath()
    context.endTransparencyLayer()
    context.restoreGState()

    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

// macOS icon set: 16, 32, 128, 256 and 512 pt, each at 1x and 2x.
let sizes = [16, 32, 128, 256, 512]
var images: [String] = []
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
for pixels in Set(sizes + sizes.map { $0 * 2 }).sorted() {
    try render(pixels: pixels).write(to: iconSet.appending(path: "icon_\(pixels).png"))
}
for size in sizes {
    for factor in [1, 2] {
        images.append(
            """
                {
                  "filename" : "icon_\(size * factor).png",
                  "idiom" : "mac",
                  "scale" : "\(factor)x",
                  "size" : "\(size)x\(size)"
                }
            """
        )
    }
}
let contents = """
    {
      "images" : [
    \(images.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
try contents.write(to: iconSet.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
try render(pixels: 1024).write(to: logo)
print("Wrote \(iconSet.path(percentEncoded: false)) and \(logo.path(percentEncoded: false))")
