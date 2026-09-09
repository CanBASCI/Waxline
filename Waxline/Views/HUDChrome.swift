import SwiftUI

enum HUDChromeShape {
    case capsule
    case circle
}

extension View {
    func hudChrome(
        glass: Bool,
        fill: Color,
        stroke: Color,
        shape: HUDChromeShape = .capsule,
        tint: Color? = nil,
        interactive: Bool = true,
        light: Bool = false,
        dark: Bool = false
    ) -> some View {
        modifier(
            HUDChromeModifier(
                glass: glass,
                fill: fill,
                stroke: stroke,
                shape: shape,
                tint: tint,
                interactive: interactive,
                light: light,
                dark: dark
            )
        )
    }

    @ViewBuilder
    func hudGlassCluster(enabled: Bool, light: Bool = false) -> some View {
        if enabled {
            if #available(iOS 26.0, *) {
                if light {
                    GlassEffectContainer(spacing: 12) { self }
                        .environment(\.colorScheme, .light)
                        .colorScheme(.light)
                } else {
                    GlassEffectContainer(spacing: 12) { self }
                }
            } else if light {
                self.environment(\.colorScheme, .light).colorScheme(.light)
            } else {
                self
            }
        } else {
            self
        }
    }
}

private struct HUDChromeModifier: ViewModifier {
    var glass: Bool
    var fill: Color
    var stroke: Color
    var shape: HUDChromeShape
    var tint: Color?
    var interactive: Bool
    var light: Bool
    var dark: Bool

    func body(content: Content) -> some View {
        switch shape {
        case .capsule:
            chrome(content, Capsule())
        case .circle:
            chrome(content, Circle())
        }
    }

    @ViewBuilder
    private func chrome<S: Shape>(_ content: Content, _ shape: S) -> some View {
        if glass {
            if #available(iOS 26.0, *) {
                if light {
                    content
                        .environment(\.colorScheme, .light)
                        .colorScheme(.light)
                        .glassEffect(glassStyle, in: shape)
                } else if dark {
                    content
                        .environment(\.colorScheme, .dark)
                        .colorScheme(.dark)
                        .glassEffect(glassStyle, in: shape)
                } else {
                    content.glassEffect(glassStyle, in: shape)
                }
            } else if light {
                content
                    .environment(\.colorScheme, .light)
                    .background(.ultraThinMaterial, in: shape)
            } else if dark {
                content
                    .environment(\.colorScheme, .dark)
                    .background(.ultraThinMaterial, in: shape)
            } else {
                content.background(.ultraThinMaterial, in: shape)
            }
        } else {
            content
                .background(fill, in: shape)
                .overlay {
                    shape.stroke(stroke, lineWidth: 1)
                }
        }
    }

    @available(iOS 26.0, *)
    private var glassStyle: Glass {
        var style = Glass.regular
        if let tint {
            style = style.tint(tint)
        } else if light {
            style = style.tint(Color(red: 0.86, green: 0.91, blue: 0.97))
        } else if dark {
            style = style.tint(Color.black)
        }
        if interactive {
            style = style.interactive()
        }
        return style
    }
}
