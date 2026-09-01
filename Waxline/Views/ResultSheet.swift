import SwiftUI

struct ResultSheet: View {
    var game: GameState
    var onAgain: () -> Void
    var onMenu: () -> Void
    @Environment(SettingsStore.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    var body: some View {
        VStack(spacing: 20) {
            SealMark(color: badgeColor)
                .frame(width: 72, height: 72)
                .padding(.top, 12)
            Text(title)
                .font(.system(.title, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink(dark: isDark))
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                if game.mode != .gameCenter {
                    Button(t("play_again"), action: onAgain)
                        .buttonStyle(WaxButtonStyle(fill: Theme.waxRed))
                }
                Button(t("menu"), action: onMenu)
                    .buttonStyle(WaxButtonStyle(fill: Theme.ink(dark: isDark), label: isDark ? Theme.canvas(dark: true) : Theme.cream))
            }
            .padding(.horizontal, 20)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas(dark: isDark))
        .preferredColorScheme(isDark ? .dark : .light)
    }

    private var isDark: Bool { settings.boardDark }

    private var title: String {
        switch game.status {
        case .draw:
            return t("draw")
        case .playing:
            return ""
        case .won(let player, _):
            if case .ai = game.mode {
                return player == .red ? t("you_win") : t("you_lose")
            }
            if game.mode == .gameCenter, let match = gameCenter.activeMatch {
                let local = gameCenter.localPlayerColor(in: match)
                return player == local ? t("you_win") : t("you_lose")
            }
            if settings.sealPalette == .mono {
                return player == .red ? t("black_wins") : t("white_wins")
            }
            return player == .red ? t("red_wins") : t("indigo_wins")
        }
    }

    private var badgeColor: Color {
        switch game.status {
        case .won(let player, _):
            Theme.seal(player, palette: settings.sealPalette)
        default:
            Theme.gold
        }
    }
}

struct WaxButtonStyle: ButtonStyle {
    var fill: Color
    var label: Color = Theme.cream

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .serif).weight(.semibold))
            .foregroundStyle(label)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(fill.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
