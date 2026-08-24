// Generates Radix's 1024×1024 app icon: a rounded accent square with the app's
// signature motif — descending size bars. Run: swift Scripts/make-icon.swift <out.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let side = 1024
let sideF = CGFloat(side)

let space = CGColorSpaceCreateDeviceRGB()
guard
    let ctx = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("context") }

// Rounded squircle background with a vertical accent gradient.
let margin = sideF * 0.085
let rect = CGRect(x: margin, y: margin, width: sideF - 2 * margin, height: sideF - 2 * margin)
let corner = rect.width * 0.225
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
ctx.clip()
let colors =
    [
        CGColor(red: 0.24, green: 0.52, blue: 0.99, alpha: 1),
        CGColor(red: 0.10, green: 0.30, blue: 0.80, alpha: 1),
    ] as CFArray
let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(
    gradient, start: CGPoint(x: rect.minX, y: rect.maxY),
    end: CGPoint(x: rect.minX, y: rect.minY), options: [])
ctx.restoreGState()

// Descending size bars (the product's signature).
let widths: [CGFloat] = [1.0, 0.68, 0.46, 0.30]
let barHeight = rect.height * 0.115
let gap = rect.height * 0.075
let maxBarWidth = rect.width * 0.60
let leftX = rect.minX + rect.width * 0.18
let block = CGFloat(widths.count) * barHeight + CGFloat(widths.count - 1) * gap
var y = rect.midY + block / 2 - barHeight
for width in widths {
    let barRect = CGRect(x: leftX, y: y, width: maxBarWidth * width, height: barHeight)
    ctx.addPath(
        CGPath(
            roundedRect: barRect, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2,
            transform: nil))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.fillPath()
    y -= (barHeight + gap)
}

guard let image = ctx.makeImage(),
    let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: outputPath) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("image") }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outputPath)")
