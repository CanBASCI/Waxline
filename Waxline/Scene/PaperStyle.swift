import ImageIO
import UIKit
@preconcurrency import SceneKit

enum PaperStyle {
    static let cream = UIColor(red: 0.96, green: 0.91, blue: 0.82, alpha: 1)
    static let creamDark = UIColor(red: 0.92, green: 0.86, blue: 0.75, alpha: 1)
    static let tableCream = UIColor(red: 0.90, green: 0.82, blue: 0.68, alpha: 1)
    static let cellWell = UIColor(red: 0.93, green: 0.87, blue: 0.77, alpha: 1)
    static let paperEdge = UIColor(red: 0.90, green: 0.84, blue: 0.72, alpha: 1)
    static let studio = UIColor(red: 0.16, green: 0.12, blue: 0.09, alpha: 1)
    static let darkCanvas = UIColor(red: 0.10, green: 0.08, blue: 0.07, alpha: 1)
    static let ink = UIColor(red: 0.24, green: 0.16, blue: 0.12, alpha: 1)
    static let waxRed = UIColor(red: 0.69, green: 0.13, blue: 0.18, alpha: 1)
    static let waxIndigo = UIColor(red: 0.18, green: 0.16, blue: 0.42, alpha: 1)
    static let waxCinnabar = UIColor(red: 0.76, green: 0.16, blue: 0.18, alpha: 1)
    static let waxPlum = UIColor(red: 0.15, green: 0.14, blue: 0.15, alpha: 1)
    static let gold = UIColor(red: 0.72, green: 0.55, blue: 0.28, alpha: 1)

    private static let woodMap = makeWood(size: 512)
    private static let graniteMap = makeGranite(size: 512)
    private static let cherryMap = makeCherry(size: 512)
    private static let washiMap = makeWashi(size: 512)
    private static let waxMap = makeWax(size: 256)
    private static var jpegCache: [String: UIImage] = [:]
    private static var sakuraTableCache: [SakuraTableTheme: SCNMaterial] = [:]
    private static var sakuraTabletCache: [String: SCNMaterial] = [:]

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

    static let waxBlack = UIColor(red: 0.10, green: 0.09, blue: 0.08, alpha: 1)
    static let waxWhite = UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)

    static func waxColor(for player: Player, palette: SealPalette, skin: GameSkin = .classic) -> UIColor {
        if skin == .sakura {
            switch (palette, player) {
            case (.classic, .red): waxCinnabar
            case (.classic, .indigo): waxPlum
            case (.mono, .red): waxBlack
            case (.mono, .indigo): waxWhite
            }
        } else {
            switch (palette, player) {
            case (.classic, .red): waxRed
            case (.classic, .indigo): waxIndigo
            case (.mono, .red): waxBlack
            case (.mono, .indigo): waxWhite
            }
        }
    }

    static func tableMaterial(
        _ finish: TableFinish,
        skin: GameSkin = .classic,
        sakuraTable: SakuraTableTheme = .oak
    ) -> SCNMaterial {
        if skin == .sakura {
            return sakuraTableMaterial(sakuraTable)
        }
        let material = woodMaterial()
        switch finish {
        case .walnut:
            break
        case .ebony:
            material.multiply.contents = UIColor(red: 0.30, green: 0.24, blue: 0.20, alpha: 1)
        case .oak:
            material.multiply.contents = UIColor(red: 0.95, green: 0.78, blue: 0.52, alpha: 1)
        }
        return material
    }

    static func tabletMaterial(
        _ finish: TabletFinish,
        recessed: Bool,
        offset: Float = 0,
        skin: GameSkin = .classic,
        sakuraTablet: SakuraTabletTheme = .grey
    ) -> SCNMaterial {
        if skin == .sakura {
            return sakuraTabletMaterial(sakuraTablet, recessed: recessed, offset: offset)
        }
        let material = graniteMaterial(dark: recessed, offset: offset)
        switch finish {
        case .granite:
            break
        case .slate:
            material.multiply.contents = UIColor(red: 0.52, green: 0.58, blue: 0.66, alpha: 1)
        case .sand:
            material.multiply.contents = UIColor(red: 0.90, green: 0.80, blue: 0.64, alpha: 1)
        }
        return material
    }

    static func sakuraTableMaterial(_ theme: SakuraTableTheme = .oak) -> SCNMaterial {
        if let cached = sakuraTableCache[theme] {
            return cached
        }
        if let color = bundleJPEG(theme.colorResource) {
            let scale: Float = theme == .oak ? 2.6 : 2.2
            let material = textured(color, roughness: 0.44, metalness: 0.03)
            applyRepeat(material, scale: scale)
            sakuraTableCache[theme] = material
            return material
        }
        let material = textured(cherryMap, roughness: 0.42, metalness: 0.03)
        applyRepeat(material, scale: 3.2)
        return material
    }

    static func sakuraTabletMaterial(_ theme: SakuraTabletTheme = .grey, recessed: Bool, offset: Float = 0) -> SCNMaterial {
        let cacheKey = "\(theme.rawValue)-\(recessed)"
        if let cached = sakuraTabletCache[cacheKey] {
            return cached
        }
        if theme == .glass {
            let material = sakuraGlassMaterial(recessed: recessed)
            sakuraTabletCache[cacheKey] = material
            return material
        }
        if let name = theme.colorResource, let color = bundleJPEG(name) {
            let scale: Float = 1.85
            let material = textured(color, roughness: recessed ? 0.68 : 0.52, metalness: 0.03)
            applyRepeat(material, scale: scale, offset: offset)
            if recessed {
                material.multiply.contents = UIColor(red: 0.52, green: 0.53, blue: 0.56, alpha: 1)
            } else if theme == .grey {
                material.multiply.contents = UIColor(red: 0.70, green: 0.71, blue: 0.74, alpha: 1)
            }
            sakuraTabletCache[cacheKey] = material
            return material
        }
        let material = textured(washiMap, roughness: recessed ? 0.78 : 0.62, metalness: 0.0)
        applyRepeat(material, scale: 1.7, offset: offset)
        if recessed {
            material.multiply.contents = UIColor(red: 0.78, green: 0.74, blue: 0.72, alpha: 1)
        }
        return material
    }

    static func sakuraGlassMaterial(recessed: Bool) -> SCNMaterial {
        let material = SCNMaterial()
        if recessed {
            material.diffuse.contents = UIColor(red: 0.90, green: 0.95, blue: 0.98, alpha: 0.42)
            material.transparency = 0.38
            material.shininess = 48
        } else {
            material.diffuse.contents = UIColor(red: 0.94, green: 0.98, blue: 1.0, alpha: 0.08)
            material.transparency = 0.90
            material.shininess = 96
        }
        material.ambient.contents = UIColor.white.withAlphaComponent(0.04)
        material.specular.contents = UIColor.white
        material.transparent.contents = UIColor.white
        material.lightingModel = .phong
        material.blendMode = .alpha
        material.transparencyMode = .singleLayer
        material.isDoubleSided = true
        material.writesToDepthBuffer = recessed
        material.readsFromDepthBuffer = true
        material.locksAmbientWithDiffuse = false
        return material
    }

    static func waxMaterial(color: UIColor, skin: GameSkin = .classic) -> SCNMaterial {
        let material = SCNMaterial()
        if skin == .sakura {
            material.diffuse.contents = waxMap
            material.multiply.contents = color
            material.roughness.contents = 0.16
            material.metalness.contents = 0.10
            material.specular.contents = UIColor.white.withAlphaComponent(0.55)
        } else {
            material.diffuse.contents = color
            material.roughness.contents = 0.22
            material.metalness.contents = 0.08
            material.specular.contents = UIColor.white.withAlphaComponent(0.45)
        }
        material.lightingModel = .physicallyBased
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        return material
    }

    private static var waxCube: [UIImage]?
    private static var sakuraCube: [UIImage]?

    static func waxLightingCube() -> [UIImage] {
        if let waxCube { return waxCube }
        let cube = lightingCube(
            UIColor(red: 1.00, green: 0.94, blue: 0.84, alpha: 1),
            UIColor(red: 0.42, green: 0.36, blue: 0.30, alpha: 1),
            UIColor(red: 1.00, green: 0.98, blue: 0.94, alpha: 1),
            UIColor(red: 0.38, green: 0.32, blue: 0.26, alpha: 1),
            UIColor(red: 0.92, green: 0.86, blue: 0.74, alpha: 1),
            UIColor(red: 0.40, green: 0.34, blue: 0.28, alpha: 1)
        )
        waxCube = cube
        return cube
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

    private static func lightingCube(_ colors: UIColor...) -> [UIImage] {
        let size = CGSize(width: 16, height: 16)
        return colors.map { color in
            UIGraphicsImageRenderer(size: size).image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
        }
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

    private static func makeCherry(size: Int) -> UIImage {
        paint(size: size) { x, y in
            let fx = CGFloat(x)
            let fy = CGFloat(y)
            let n = hash(x, y, 23)
            let warp = sin(fy * 0.022) * 16 + sin(fy * 0.08) * 4.5 + n * 1.6
            let wave = sin((fx + warp) * 0.33)
            let band = 0.5 + 0.5 * wave
            let line = pow(1 - abs(wave), 20)
            let pore = hash(x, y, 61) * 0.028
            let t = band * 0.52 + 0.24
            return (
                0.30 + t * 0.44 - line * 0.13 - pore,
                0.12 + t * 0.30 - line * 0.07 - pore,
                0.08 + t * 0.20 - line * 0.04
            )
        }
    }

    private static func makeWashi(size: Int) -> UIImage {
        paint(size: size) { x, y in
            let pulp = hash(x / 5, y / 5, 11) * 0.045 + hash(x, y, 29) * 0.02
            func fiber(_ seed: Int, ax: CGFloat, ay: CGFloat, freq: CGFloat) -> CGFloat {
                let w = hash(x, y, seed)
                let s = sin((CGFloat(x) * ax + CGFloat(y) * ay) * freq + w * 5.5)
                return pow(max(0, 1 - abs(s) * 7.2), 1.6)
            }
            let strands = min(1, fiber(3, ax: 0.12, ay: 0.028, freq: 0.16) * 0.55
                + fiber(8, ax: -0.038, ay: 0.10, freq: 0.13) * 0.42
                + fiber(21, ax: 0.07, ay: -0.055, freq: 0.21) * 0.32)
            let baseR: CGFloat = 0.95
            let baseG: CGFloat = 0.87
            let baseB: CGFloat = 0.81
            return (
                baseR - pulp * 0.10 - strands * 0.06,
                baseG - pulp * 0.10 - strands * 0.14,
                baseB - pulp * 0.08 - strands * 0.16
            )
        }
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
