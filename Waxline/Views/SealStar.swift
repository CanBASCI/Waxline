import SwiftUI
import UIKit

nonisolated enum SealStarGeometry: Sendable {
    static let defaultInnerRatio: CGFloat = 0.09 / 0.22
    static let brandInnerRatio: CGFloat = 64 / 150

    static func points(
        center: CGPoint,
        outer: CGFloat,
        innerRatio: CGFloat = defaultInnerRatio
    ) -> [CGPoint] {
        (0..<16).map { index in
            let radius = index.isMultiple(of: 2) ? outer : outer * innerRatio
            let angle = CGFloat(index) * .pi / 8 - .pi / 2
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    static func bezierPath(
        center: CGPoint = .zero,
        outer: CGFloat,
        innerRatio: CGFloat = defaultInnerRatio
    ) -> UIBezierPath {
        let path = UIBezierPath()
        let pts = points(center: center, outer: outer, innerRatio: innerRatio)
        guard let first = pts.first else { return path }
        path.move(to: first)
        for point in pts.dropFirst() {
            path.addLine(to: point)
        }
        path.close()
        return path
    }
}

struct SealStar: Shape {
    var innerRatio: CGFloat = 0.09 / 0.22

    func path(in rect: CGRect) -> Path {
        let outer = min(rect.width, rect.height) / 2
        let pts = SealStarGeometry.points(
            center: CGPoint(x: rect.midX, y: rect.midY),
            outer: outer,
            innerRatio: innerRatio
        )
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for point in pts.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
