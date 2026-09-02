import SwiftUI

struct DigitalBackdrop: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
                SIMD2(0, 0.5), SIMD2(0.52, 0.48), SIMD2(1, 0.5),
                SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)
            ],
            colors: [
                Color(red: 0.18, green: 0.28, blue: 0.52),
                Color(red: 0.32, green: 0.22, blue: 0.56),
                Color(red: 0.16, green: 0.38, blue: 0.54),
                Color(red: 0.22, green: 0.18, blue: 0.44),
                Color(red: 0.48, green: 0.30, blue: 0.62),
                Color(red: 0.14, green: 0.32, blue: 0.50),
                Color(red: 0.12, green: 0.16, blue: 0.36),
                Color(red: 0.26, green: 0.16, blue: 0.42),
                Color(red: 0.10, green: 0.24, blue: 0.40)
            ]
        )
        .ignoresSafeArea()
    }
}

struct NativeGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        }
    }
}

struct NativeGlassButton: ViewModifier {
    var prominent: Bool = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent).controlSize(.large)
            } else {
                content.buttonStyle(.glass).controlSize(.large)
            }
        } else {
            content.buttonStyle(.bordered).controlSize(.large)
        }
    }
}

struct NativeGlassIconButton: View {
    var systemName: String
    var accessibility: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityLabel(accessibility)
        .modifier(NativeGlassCircle())
    }
}

struct DigitalSheetBackground: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            if #available(iOS 26.0, *) {
                content.presentationBackground(.clear)
            } else {
                content.presentationBackground(.ultraThinMaterial)
            }
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func digitalTurnChrome(enabled: Bool) -> some View {
        if enabled {
            if #available(iOS 26.0, *) {
                glassEffect(.regular, in: Capsule())
            } else {
                background(.ultraThinMaterial, in: Capsule())
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func digitalGlass<S: Shape>(
        _ style: DigitalGlassStyle = .regular,
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(style.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            background(.ultraThinMaterial.opacity(0.85), in: shape)
                .overlay {
                    if let tint {
                        shape.fill(tint.opacity(0.45))
                    }
                }
        }
    }
}

enum DigitalGlassStyle {
    case regular
    case clear

    @available(iOS 26.0, *)
    func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass: Glass = self == .clear ? .clear : .regular
        glass = glass.interactive(interactive)
        if let tint {
            glass = glass.tint(tint)
        }
        return glass
    }
}

struct DigitalSeal: View {
    var color: Color
    var motif: Color
    var winning: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        SealStar()
            .fill(motif)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .digitalGlass(.regular, in: shape, tint: color, interactive: true)
            .scaleEffect(winning ? 1.1 : 1)
    }
}
