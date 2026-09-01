import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

NSColor(srgbRed: 0.96, green: 0.91, blue: 0.82, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

let sealRect = NSRect(x: 212, y: 212, width: 600, height: 600)
let seal = NSBezierPath(roundedRect: sealRect, xRadius: 168, yRadius: 168)
NSColor(srgbRed: 0.69, green: 0.13, blue: 0.18, alpha: 1).setFill()
seal.fill()

let inset = sealRect.insetBy(dx: 28, dy: 28)
let ring = NSBezierPath(roundedRect: inset, xRadius: 148, yRadius: 148)
NSColor(srgbRed: 0.95, green: 0.82, blue: 0.45, alpha: 0.55).setStroke()
ring.lineWidth = 10
ring.stroke()

let cx = CGFloat(size) / 2
let cy = CGFloat(size) / 2
let star = NSBezierPath()
let points = 8
for i in 0..<(points * 2) {
    let radius: CGFloat = i.isMultiple(of: 2) ? 150 : 64
    let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
    let point = NSPoint(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius)
    if i == 0 { star.move(to: point) } else { star.line(to: point) }
}
star.close()
NSColor(srgbRed: 0.95, green: 0.82, blue: 0.45, alpha: 1).setFill()
star.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("icon export failed")
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: url)
print("Wrote \(url.path)")
