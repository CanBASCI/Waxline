import UIKit
@preconcurrency import SceneKit

enum PaperStyle {
    static let cream = UIColor(red: 0.96, green: 0.91, blue: 0.82, alpha: 1)
    static let creamDark = UIColor(red: 0.92, green: 0.86, blue: 0.75, alpha: 1)
    static let tableCream = UIColor(red: 0.90, green: 0.82, blue: 0.68, alpha: 1)
    static let cellWell = UIColor(red: 0.93, green: 0.87, blue: 0.77, alpha: 1)
    static let paperEdge = UIColor(red: 0.90, green: 0.84, blue: 0.72, alpha: 1)
    static let studio = UIColor(red: 0.16, green: 0.12, blue: 0.09, alpha: 1)
    static let ink = UIColor(red: 0.24, green: 0.16, blue: 0.12, alpha: 1)
    static let waxRed = UIColor(red: 0.69, green: 0.13, blue: 0.18, alpha: 1)
    static let waxIndigo = UIColor(red: 0.18, green: 0.16, blue: 0.42, alpha: 1)
    static let gold = UIColor(red: 0.72, green: 0.55, blue: 0.28, alpha: 1)

    private static let woodMap = makeWood(size: 512)
    private static let graniteMap = makeGranite(size: 512)

    static func paperMaterial() -> SCNMaterial {
        matte(cream)
    }

    static func unlit(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.locksAmbientWithDiffuse = true
        return material
    }

    static func matte(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.specular.contents = UIColor.black
        material.lightingModel = .lambert
        material.locksAmbientWithDiffuse = true
        return material
    }

    static func woodMaterial() -> SCNMaterial {
        let material = textured(woodMap, roughness: 0.46, metalness: 0.04)
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(5, 5, 1)
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        return material
    }

    static func graniteMaterial(dark: Bool = false, offset: Float = 0) -> SCNMaterial {
        let material = textured(graniteMap, roughness: dark ? 0.62 : 0.48, metalness: 0.06)
        var transform = SCNMatrix4MakeScale(2.4, 2.4, 1)
        if offset != 0 {
            transform = SCNMatrix4Translate(transform, offset, offset * 0.55, 0)
        }
        material.diffuse.contentsTransform = transform
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        if dark {
            material.multiply.contents = UIColor(red: 0.78, green: 0.80, blue: 0.82, alpha: 1)
        }
        return material
    }

    static func waxMaterial(color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.roughness.contents = 0.22
        material.metalness.contents = 0.08
        material.lightingModel = .physicallyBased
        material.specular.contents = UIColor.white.withAlphaComponent(0.45)
        return material
    }

    static func waxLightingCube() -> [UIImage] {
        func swatch(_ color: UIColor) -> UIImage {
            let size = CGSize(width: 16, height: 16)
            return UIGraphicsImageRenderer(size: size).image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
        }
        return [
            swatch(UIColor(red: 1.00, green: 0.94, blue: 0.84, alpha: 1)),
            swatch(UIColor(red: 0.42, green: 0.36, blue: 0.30, alpha: 1)),
            swatch(UIColor(red: 1.00, green: 0.98, blue: 0.94, alpha: 1)),
            swatch(UIColor(red: 0.38, green: 0.32, blue: 0.26, alpha: 1)),
            swatch(UIColor(red: 0.92, green: 0.86, blue: 0.74, alpha: 1)),
            swatch(UIColor(red: 0.40, green: 0.34, blue: 0.28, alpha: 1))
        ]
    }

    static func starPath(scale: CGFloat = 1) -> UIBezierPath {
        let path = UIBezierPath()
        let points = 8
        let outer: CGFloat = 0.22 * scale
        let inner: CGFloat = 0.09 * scale
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.close()
        return path
    }

    private static func textured(_ image: UIImage, roughness: CGFloat, metalness: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.roughness.contents = roughness
        material.metalness.contents = metalness
        material.lightingModel = .physicallyBased
        material.locksAmbientWithDiffuse = true
        return material
    }

    private static func hash(_ x: Int, _ y: Int, _ seed: Int) -> CGFloat {
        var h = UInt32(bitPattern: Int32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263 &+ seed))
        h ^= h >> 13
        h &*= 1274126177
        h ^= h >> 16
        return CGFloat(h & 1023) / 1023
    }

    private static func makeWood(size: Int) -> UIImage {
        paint(size: size) { x, y in
            let fx = CGFloat(x)
            let fy = CGFloat(y)
            let n = hash(x, y, 19)
            let warp = sin(fy * 0.03) * 14 + sin(fy * 0.11) * 3 + n * 2.2
            let wave = sin((fx + warp) * 0.25)
            let band = 0.5 + 0.5 * wave
            let line = pow(1 - abs(wave), 18)
            let pore = hash(x, y, 91) * 0.035
            let t = band * 0.62 + 0.12
            return (
                0.17 + t * 0.30 - line * 0.11 - pore,
                0.08 + t * 0.15 - line * 0.06 - pore,
                0.04 + t * 0.07 - line * 0.03
            )
        }
    }

    private static func makeGranite(size: Int) -> UIImage {
        paint(size: size) { x, y in
            let a = hash(x, y, 11)
            let b = hash(x / 2, y / 2, 29)
            let c = hash(x, y, 73)
            let base: CGFloat = 0.42 + b * 0.10
            if c > 0.97 {
                return (0.82, 0.84, 0.86)
            }
            if c < 0.045 {
                return (0.12, 0.12, 0.13)
            }
            if a > 0.86 {
                return (0.55 + a * 0.12, 0.52, 0.48)
            }
            return (
                base * 0.92,
                base * 0.94,
                base
            )
        }
    }

    private static func paint(size: Int, pixel: (Int, Int) -> (CGFloat, CGFloat, CGFloat)) -> UIImage {
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                var (r, g, b) = pixel(x, y)
                r = min(max(r, 0), 1)
                g = min(max(g, 0), 1)
                b = min(max(b, 0), 1)
                let i = (y * size + x) * 4
                bytes[i] = UInt8(r * 255)
                bytes[i + 1] = UInt8(g * 255)
                bytes[i + 2] = UInt8(b * 255)
            }
        }
        let data = Data(bytes)
        let provider = CGDataProvider(data: data as CFData)!
        let cgImage = CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
        return UIImage(cgImage: cgImage)
    }
}
