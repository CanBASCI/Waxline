import ImageIO
import UIKit
@preconcurrency import SceneKit

enum PaperStyle {
    static let cream = UIColor(red: 0.96, green: 0.91, blue: 0.82, alpha: 1)
    static let waxCinnabar = UIColor(red: 0.76, green: 0.16, blue: 0.18, alpha: 1)
    static let waxDusk = UIColor(red: 0.29, green: 0.25, blue: 0.42, alpha: 1)
    static let waxBlack = UIColor(red: 0.10, green: 0.09, blue: 0.08, alpha: 1)
    static let waxWhite = UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
    static let waxMagenta = UIColor(red: 0.95, green: 0.18, blue: 0.58, alpha: 1)
    static let waxCyan = UIColor(red: 0.18, green: 0.82, blue: 0.96, alpha: 1)

    private static let waxMap = makeWax(size: 256)
    private static var jpegCache: [String: UIImage] = [:]
    private static var sakuraTabletCache: [String: SCNMaterial] = [:]
    private static var sakuraCube: [UIImage]?

    static func unlit(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.locksAmbientWithDiffuse = true
        return material
    }

    static func waxColor(for player: Player, palette: SealPalette) -> UIColor {
        switch (palette, player) {
        case (.classic, .red): waxCinnabar
        case (.classic, .indigo): waxDusk
        case (.mono, .red): waxBlack
        case (.mono, .indigo): waxWhite
        case (.neon, .red): waxMagenta
        case (.neon, .indigo): waxCyan
        }
    }

    static func sakuraTabletMaterial(
        _ theme: SakuraTabletTheme = .charcoal,
        recessed: Bool,
        offset: Float = 0
    ) -> SCNMaterial {
        let cacheKey = "\(theme.rawValue)-\(recessed)"
        if let cached = sakuraTabletCache[cacheKey] {
            return cached
        }
        if let color = bundleJPEG(theme.colorResource) {
            let roughness: CGFloat
            switch theme {
            case .blossom: roughness = recessed ? 0.58 : 0.42
            case .charcoal: roughness = recessed ? 0.68 : 0.52
            case .neon: roughness = recessed ? 0.52 : 0.34
            }
            let material = textured(color, roughness: roughness, metalness: theme == .neon ? 0.08 : 0.03)
            applyRepeat(material, scale: 1.85, offset: offset)
            if recessed {
                switch theme {
                case .blossom:
                    material.multiply.contents = UIColor(red: 0.72, green: 0.54, blue: 0.58, alpha: 1)
                case .charcoal:
                    material.multiply.contents = UIColor(red: 0.52, green: 0.53, blue: 0.56, alpha: 1)
                case .neon:
                    material.multiply.contents = UIColor(red: 0.22, green: 0.16, blue: 0.32, alpha: 1)
                }
            }
            sakuraTabletCache[cacheKey] = material
            return material
        }
        return unlit(fallbackColor(for: theme))
    }

    private static func fallbackColor(for theme: SakuraTabletTheme) -> UIColor {
        switch theme {
        case .blossom: UIColor(red: 0.78, green: 0.58, blue: 0.62, alpha: 1)
        case .charcoal: UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1)
        case .neon: UIColor(red: 0.07, green: 0.10, blue: 0.22, alpha: 1)
        }
    }

    static func waxMaterial(color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = waxMap
        material.multiply.contents = color
        material.roughness.contents = 0.16
        material.metalness.contents = 0.10
        material.specular.contents = UIColor.white.withAlphaComponent(0.55)
        material.lightingModel = .physicallyBased
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        return material
    }

    static func sakuraLightingCube() -> [UIImage] {
        if let sakuraCube { return sakuraCube }
        let cube = lightingCube(
            UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1),
            UIColor(red: 0.32, green: 0.32, blue: 0.34, alpha: 1),
            UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
            UIColor(red: 0.30, green: 0.30, blue: 0.32, alpha: 1),
            UIColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1),
            UIColor(red: 0.34, green: 0.34, blue: 0.36, alpha: 1)
        )
        sakuraCube = cube
        return cube
    }

    static func starPath(scale: CGFloat = 1) -> UIBezierPath {
        SealStarGeometry.bezierPath(outer: 0.22 * scale)
    }

    static func bundleImage(_ name: String) -> UIImage? {
        bundleJPEG(name)
    }

    private static func lightingCube(_ colors: UIColor...) -> [UIImage] {
        let size = CGSize(width: 16, height: 16)
        return colors.map { color in
            UIGraphicsImageRenderer(size: size).image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
        }
    }

    private static func applyRepeat(_ material: SCNMaterial, scale: Float, offset: Float = 0) {
        var transform = SCNMatrix4MakeScale(scale, scale, 1)
        if offset != 0 {
            transform = SCNMatrix4Translate(transform, offset, offset * 0.4, 0)
        }
        material.diffuse.contentsTransform = transform
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
    }

    private static func bundleJPEG(_ name: String) -> UIImage? {
        if let cached = jpegCache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 512
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        jpegCache[name] = image
        return image
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

    nonisolated private static func hash(_ x: Int, _ y: Int, _ seed: Int) -> CGFloat {
        var h = UInt32(bitPattern: Int32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263 &+ seed))
        h ^= h >> 13
        h &*= 1274126177
        h ^= h >> 16
        return CGFloat(h & 1023) / 1023
    }

    private static func makeWax(size: Int) -> UIImage {
        paint(size: size) { x, y in
            let blob = 0.86 + hash(x / 8, y / 8, 31) * 0.10 + hash(x / 3, y / 3, 7) * 0.05
            let grain = hash(x, y, 19) * 0.04
            let bubble = hash(x, y, 53) > 0.965 ? 0.10 : 0
            let v = min(max(blob + grain + bubble, 0.78), 1)
            return (v, v * 0.98, v * 0.96)
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
