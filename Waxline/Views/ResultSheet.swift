import SwiftUI

struct ResultSheet: View {
    var game: GameState
    var skin: GameSkin = .classic
    var seals: SealPalette = .classic
    var onAgain: () -> Void
    var onMenu: () -> Void
    @Environment(SettingsStore.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    var body: some View {
        VStack(spacing: 14) {
            SealMark(
                color: badgeColor,
                motif: badgeMotif,
                outline: badgeOutline
            )
            .frame(width: 44, height: 44)
            .padding(.top, 8)

            Text(title)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                if game.mode != .gameCenter {
                    resultAction(t("play_again"), prominent: true, action: onAgain)
                }
                resultAction(t("menu"), prominent: false, action: onMenu)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(248)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        .preferredColorScheme(sheetScheme)
    }

    private func resultAction(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .serif).weight(prominent ? .semibold : .medium))
                .foregroundStyle(prominent ? prominentLabel : secondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(prominent ? prominentFill : secondaryFill, in: Capsule())
                .overlay {
                    Capsule().stroke(prominent ? Color.clear : secondaryStroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var sheetDark: Bool {
        if skin == .sakura { return seals == .mono }
        return settings.boardDark
    }

    private var sheetScheme: ColorScheme { sheetDark ? .dark : .light }

    private var prominentFill: Color {
        sheetDark ? Color.white.opacity(0.16) : Theme.waxRed
    }

    private var prominentLabel: Color {
        sheetDark ? Theme.ink(dark: true) : Theme.cream
    }

    private var secondaryFill: Color {
        sheetDark ? Color.white.opacity(0.08) : Theme.chipFill(dark: false)
    }

    private var secondaryLabel: Color {
        Theme.ink(dark: sheetDark)
    }

    private var secondaryStroke: Color {
        Theme.ink(dark: sheetDark).opacity(0.35)
    }

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
            if seals == .mono {
                return player == .red ? t("black_wins") : t("white_wins")
            }
            return player == .red ? t("red_wins") : t("indigo_wins")
        }
    }

    private var badgeColor: Color {
        switch game.status {
        case .won(let player, _):
            Theme.seal(player, palette: seals, skin: skin)
        default:
            Theme.gold
        }
    }

    private var isWhiteWin: Bool {
        if case .won(let player, _) = game.status {
            return seals == .mono && player == .indigo
        }
        return false
    }

    private var badgeMotif: Color {
        isWhiteWin ? Theme.waxBlack : Theme.gold
    }

    private var badgeOutline: Color? {
        guard seals == .mono else { return nil }
        if sheetDark, case .won(let player, _) = game.status, player == .red {
            return Theme.ink(dark: true).opacity(0.7)
        }
        if isWhiteWin {
            return Theme.ink.opacity(0.4)
        }
        return nil
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
