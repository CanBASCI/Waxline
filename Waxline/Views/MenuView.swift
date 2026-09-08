import SwiftUI

struct MenuView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter

    var playback: MenuIntroPlayback
    var onAI: () -> Void
    var onGameCenter: () -> Void
    var onSettings: () -> Void
    var onHowToPlay: () -> Void

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    private var titleIntroOffset: CGFloat {
        playback.didFinish ? 0 : (1 - playback.progress) * 108
    }

    private var menuFont: Font { .system(.body, design: .serif).weight(.medium) }
    private var menuLinkFont: Font { .system(size: 18, weight: .medium, design: .serif) }
    @State private var idle = false

    var body: some View {
        ZStack {
            MenuSakuraBackdrop(playback: playback)
                .ignoresSafeArea()

            VStack(alignment: .trailing, spacing: 18) {
                VStack(alignment: .trailing, spacing: 8) {
                    BrandMark()
                        .frame(width: 68, height: 68)
                    Text(t("app_name"))
                        .font(.system(.title, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .offset(y: titleIntroOffset)
                }
                .shadow(color: Color.white.opacity(0.75), radius: 8)
                .opacity(playback.isReady ? 1 : 0)
                .transaction { $0.animation = nil }

                VStack(alignment: .trailing, spacing: 14) {
                    textLink(t("menu_ai"), index: 0, action: onAI)
                    VStack(alignment: .trailing, spacing: 4) {
                        gameCenterLink(index: 1)
                        Text(t("gc_sign_in"))
                            .font(.footnote)
                            .foregroundStyle(Theme.ink.opacity(0.55))
                            .opacity(gameCenter.isAuthenticated || !playback.didFinish ? 0 : 1)
                    }
                    textLink(t("menu_how_to_play"), index: 2, action: onHowToPlay)
                    textLink(t("menu_settings"), index: 3, action: onSettings)
                }
                .font(menuLinkFont)
                .foregroundStyle(Theme.ink)
                .shadow(color: Color.white.opacity(0.75), radius: 8)
                .allowsHitTesting(playback.didFinish)
            }
            .padding(.trailing, 22)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if playback.isReady, !playback.didFinish {
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
                .safeAreaPadding(.top)
                .transaction { $0.animation = nil }
            }
        }
        .onAppear {
            if playback.didFinish { idle = true }
            if gameCenter.isAuthenticated {
                Task { await gameCenter.refreshPendingInvites() }
            }
        }
        .onChange(of: playback.didFinish) { _, finished in
            guard finished else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                idle = true
            }
        }
    }

    private func textLink(
        _ title: String,
        index: Int,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.38)
            .menuLineMotion(revealed: playback.didFinish, idle: idle, index: index)
    }

    private func gameCenterLink(index: Int) -> some View {
        Button(action: onGameCenter) {
            HStack(spacing: 8) {
                if gameCenter.pendingInviteCount > 0 {
                    Text("\(gameCenter.pendingInviteCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, gameCenter.pendingInviteCount > 9 ? 5 : 0)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.red, in: Capsule())
                        .accessibilityLabel(t("gc_invites"))
                }
                Text(t("menu_gamecenter"))
            }
        }
        .buttonStyle(.plain)
        .disabled(!gameCenter.isAuthenticated)
        .opacity(gameCenter.isAuthenticated ? 1 : 0.38)
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

struct BrandMark: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                    .fill(Theme.waxRed)
                RoundedRectangle(cornerRadius: side * (148 / 600), style: .continuous)
                    .stroke(Theme.gold.opacity(0.55), lineWidth: max(1, side * (10 / 600)))
                    .padding(side * (28 / 600))
                SealStar(innerRatio: 64 / 150)
                    .fill(Theme.gold)
                    .frame(width: side * 0.5, height: side * 0.5)
            }
        }
        .aspectRatio(1, contentMode: .fit)
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

struct SeriesScoreRow: View {
    var series: MatchSeries
    var seals: SealPalette
    var you: Player = .red
    var sealSize: CGFloat
    var numberColor: Color

    var body: some View {
        HStack(spacing: sealSize * 0.45) {
            scoreMark(you, count: series.you)
            Text("–")
                .foregroundStyle(numberColor.opacity(0.5))
            scoreMark(you.opponent, count: series.opponent)
            if series.draws > 0 {
                scoreMark(nil, count: series.draws)
            }
        }
        .font(.system(size: sealSize * 0.62, weight: .medium, design: .serif))
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if series.draws > 0 {
            return "\(series.you)–\(series.opponent)–\(series.draws)"
        }
        return "\(series.you)–\(series.opponent)"
    }

    private func scoreMark(_ player: Player?, count: Int) -> some View {
        HStack(spacing: sealSize * 0.28) {
            SealMark(
                color: player.map { Theme.seal($0, palette: seals) } ?? Theme.gold,
                motif: motif(for: player),
                outline: outline(for: player)
            )
            .frame(width: sealSize, height: sealSize)
            Text("\(count)")
                .foregroundStyle(numberColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .frame(height: sealSize)
        }
    }

    private func motif(for player: Player?) -> Color {
        if player == nil { return Theme.waxBlack }
        if seals == .mono, player == .indigo { return Theme.waxBlack }
        return Theme.gold
    }

    private func outline(for player: Player?) -> Color? {
        guard seals == .mono else { return nil }
        if player == .indigo {
            return Theme.ink.opacity(0.4)
        }
        if player == .red {
            return Theme.ink(dark: true).opacity(0.7)
        }
        return Theme.ink.opacity(0.35)
    }
}

struct SealStar: Shape {
    var innerRatio: CGFloat = 0.09 / 0.22

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
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
