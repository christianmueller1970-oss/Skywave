// Renders an icon SVG (authored on a 1024x1024 canvas with the plate at
// 100,100 824x824 r185) to a PNG, clipping to the plate's rounded rect —
// qlmanage/WebKit ignores SVG clipPath, so we clip here instead.
// Usage: swift render-icon.swift in.svg out.png [size]
//
// Regenerate the app icon set from app-icon.svg:
//   for s in 16 32 64 128 256 512 1024; do
//     swift render-icon.swift app-icon.svg \
//       ../Skywave/Assets.xcassets/AppIcon.appiconset/icon_${s}.png $s
//   done
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let svg = NSImage(contentsOfFile: args[1]) else {
    fputs("usage: render-icon.swift in.svg out.png [size]\n", stderr)
    exit(64)
}
let size = args.count > 3 ? Int(args[3]) ?? 1024 : 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let s = CGFloat(size) / 1024
NSBezierPath(
    roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
    xRadius: 185 * s, yRadius: 185 * s
).addClip()
svg.draw(in: NSRect(x: 0, y: 0, width: size, height: size))

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: args[2]))
