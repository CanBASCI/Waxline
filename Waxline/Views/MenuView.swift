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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(color)
                .shadow(color: color.opacity(0.35), radius: 10, y: 6)
            Image(systemName: "seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.gold)
        }
    }
}
