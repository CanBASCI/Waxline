import UIKit
@preconcurrency import SceneKit

enum PaperStyle {
    static let cream = UIColor(red: 0.96, green: 0.91, blue: 0.82, alpha: 1)
    static let creamDark = UIColor(red: 0.92, green: 0.86, blue: 0.75, alpha: 1)
    static let cellWell = UIColor(red: 0.93, green: 0.87, blue: 0.77, alpha: 1)
    static let paperEdge = UIColor(red: 0.90, green: 0.84, blue: 0.72, alpha: 1)
    static let ink = UIColor(red: 0.24, green: 0.16, blue: 0.12, alpha: 1)
    static let waxRed = UIColor(red: 0.69, green: 0.13, blue: 0.18, alpha: 1)
    static let waxIndigo = UIColor(red: 0.18, green: 0.16, blue: 0.42, alpha: 1)
    static let gold = UIColor(red: 0.72, green: 0.55, blue: 0.28, alpha: 1)

    static func paperMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = cream
        material.roughness.contents = 1
        material.metalness.contents = 0
        material.specular.contents = UIColor.black
        material.lightingModel = .lambert
        material.locksAmbientWithDiffuse = true
        return material
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

    static func waxMaterial(color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.roughness.contents = 0.32
        material.metalness.contents = 0.04
        material.lightingModel = .physicallyBased
        material.specular.contents = UIColor.white.withAlphaComponent(0.35)
        return material
    }

    static func starPath() -> UIBezierPath {
        let path = UIBezierPath()
        let points = 8
        let outer: CGFloat = 0.22
        let inner: CGFloat = 0.09
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.close()
        return path
    }
}
