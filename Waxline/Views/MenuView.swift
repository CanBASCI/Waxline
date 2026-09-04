import SwiftUI

struct MenuView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter

    var playback: MenuIntroPlayback
    var onLocal: () -> Void
    var onAI: () -> Void
    var onGameCenter: () -> Void
    var onSettings: () -> Void
    var onHowToPlay: () -> Void
    var onTest: () -> Void

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    private var menuFont: Font { .system(.body, design: .serif).weight(.medium) }
    @State private var idle = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MenuSakuraBackdrop(playback: playback)

            VStack(alignment: .trailing, spacing: 18) {
                VStack(alignment: .trailing, spacing: 8) {
                    SealMark(color: Theme.waxRed)
                        .frame(width: 68, height: 68)
                    Text(t("app_name"))
                        .font(.system(.title, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .offset(y: playback.didFinish ? 0 : (1 - playback.progress) * 108)
                }
                .shadow(color: Color.white.opacity(0.75), radius: 8)
                .opacity(playback.isReady ? 1 : 0)

                VStack(alignment: .trailing, spacing: 14) {
                    textLink(t("menu_local"), index: 0, action: onLocal)
                    textLink(t("menu_ai"), index: 1, action: onAI)
                    textLink(t("menu_gamecenter"), index: 2, action: onGameCenter)
                    textLink(t("menu_how_to_play"), index: 3, action: onHowToPlay)
                    textLink(t("menu_settings"), index: 4, action: onSettings)
                    textLink(t("menu_test"), index: 5, action: onTest)
                }
                .font(menuFont)
                .foregroundStyle(Theme.ink)
                .shadow(color: Color.white.opacity(0.75), radius: 8)
                .allowsHitTesting(playback.didFinish)
                .overlay(alignment: .bottomTrailing) {
                    if !gameCenter.isAuthenticated {
                        Text(t("gc_sign_in"))
                            .font(.footnote)
                            .foregroundStyle(Theme.ink.opacity(0.55))
                            .offset(y: 18)
                            .opacity(playback.didFinish ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(.trailing, 22)
            .padding(.bottom, 36)
            .safeAreaPadding(.bottom)
            .safeAreaPadding(.trailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .safeAreaInset(edge: .top, alignment: .trailing, spacing: 0) {
            if playback.isReady, !playback.didFinish, playback.handoff < 0.2 {
                Button(action: playback.skip) {
                    Text(t("onboarding_skip"))
                        .font(menuFont)
                        .blendMode(.destinationOut)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background { SkipCutoutBackdrop() }
                        .compositingGroup()
                }
                .buttonStyle(.plain)
                .padding(.trailing, 22)
                .padding(.top, 8)
            }
        }
        .onAppear {
            if playback.didFinish { idle = true }
        }
        .onChange(of: playback.didFinish) { _, finished in
            guard finished else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                idle = true
            }
        }
    }

    private func textLink(_ title: String, index: Int, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .menuLineMotion(revealed: playback.didFinish, idle: idle, index: index)
    }
}

private struct SkipCutoutBackdrop: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: Capsule())
        } else {
            Color.clear.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct MenuLineMotion: ViewModifier {
    var revealed: Bool
    var idle: Bool
    var index: Int

    func body(content: Content) -> some View {
        content
            .offset(x: revealed ? 0 : 96)
            .opacity(revealed ? 1 : 0)
            .animation(.easeOut(duration: 0.65).delay(Double(index) * 0.09), value: revealed)
            .offset(y: idle ? -2.5 : 2.5)
            .animation(
                idle
                    ? .easeInOut(duration: 3.8).repeatForever(autoreverses: true).delay(Double(index) * 0.2)
                    : .default,
                value: idle
            )
    }
}

private extension View {
    func menuLineMotion(revealed: Bool, idle: Bool, index: Int) -> some View {
        modifier(MenuLineMotion(revealed: revealed, idle: idle, index: index))
    }
}

struct SealMark: View {
    var color: Color
    var motif: Color = Theme.gold
    var outline: Color? = nil
    var outlineWidth: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                    .fill(color)
                    .shadow(color: color.opacity(side > 40 ? 0.35 : 0.2), radius: side * 0.12, y: side * 0.08)
                    .overlay {
                        if let outline {
                            RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                                .stroke(outline, lineWidth: outlineWidth ?? max(1, side * 0.05))
                        }
                    }
                SealStar()
                    .fill(motif)
                    .frame(width: side * 0.71, height: side * 0.71)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct SealStar: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * (0.09 / 0.22)
        var path = Path()
        for index in 0..<16 {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = Double(index) * .pi / 8 - .pi / 2
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
