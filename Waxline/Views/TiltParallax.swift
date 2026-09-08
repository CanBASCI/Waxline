import CoreMotion
import SwiftUI

@Observable
final class TiltParallax {
    var x: CGFloat = 0
    var y: CGFloat = 0

    private let motion = CMMotionManager()
    private var reference: CMAttitude?
    private var running = false

    func setActive(_ active: Bool) {
        if active {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard !running else { return }
        if UIAccessibility.isReduceMotionEnabled { return }
        guard motion.isDeviceMotionAvailable else { return }
        running = true
        reference = nil
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, _ in
            guard let self, let attitude = data?.attitude.copy() as? CMAttitude else { return }
            if self.reference == nil {
                self.reference = attitude.copy() as? CMAttitude
            }
            guard let reference = self.reference else { return }
            attitude.multiply(byInverseOf: reference)
            self.x = Self.clamp(sin(attitude.roll))
            self.y = Self.clamp(sin(attitude.pitch))
        }
    }

    private func stop() {
        guard running else { return }
        running = false
        motion.stopDeviceMotionUpdates()
        reference = nil
        withAnimation(.easeOut(duration: 0.22)) {
            x = 0
            y = 0
        }
    }

    private static func clamp(_ value: Double) -> CGFloat {
        CGFloat(max(-0.55, min(0.55, value)))
    }
}

extension View {
    func tiltShift(_ tilt: TiltParallax, travel: CGFloat) -> some View {
        offset(x: -tilt.x * travel, y: tilt.y * travel)
    }
}
