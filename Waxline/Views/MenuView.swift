import SwiftUI

struct MenuView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter

    var onLocal: () -> Void
    var onAI: () -> Void
    var onGameCenter: () -> Void
    var onSettings: () -> Void
    var onHowToPlay: () -> Void

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            SealMark(color: Theme.waxRed)
                .frame(width: 92, height: 92)
            VStack(spacing: 6) {
                Text(t("app_name"))
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(t("app_subtitle"))
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.7))
            }
            .padding(.bottom, 12)

            menuButton(t("menu_local"), color: Theme.waxRed, action: onLocal)
            menuButton(t("menu_ai"), color: Theme.waxIndigo, action: onAI)
            menuButton(t("menu_gamecenter"), color: Theme.gold, action: onGameCenter)
            if !gameCenter.isAuthenticated {
                Text(t("gc_sign_in"))
                    .font(.footnote)
                    .foregroundStyle(Theme.ink.opacity(0.55))
            }

            Spacer()
            HStack(spacing: 28) {
                Button(t("menu_how_to_play"), action: onHowToPlay)
                Button(t("menu_settings"), action: onSettings)
            }
            .font(.system(.body, design: .serif).weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 28)
    }

    private func menuButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(Theme.cream)
                .background(color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
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
                    .frame(width: side * 0.58, height: side * 0.58)
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
