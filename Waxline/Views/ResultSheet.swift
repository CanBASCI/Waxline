import SwiftUI

struct ResultSheet: View {
    var game: GameState
    var seals: SealPalette = .classic
    var onAgain: () -> Void
    var onMenu: () -> Void
    @Environment(SettingsStore.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter
    @State private var confirmLeave = false

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

            if let subtitle {
                Text(subtitle)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                if showPlayAgain {
                    resultAction(
                        t("play_again"),
                        prominent: true,
                        enabled: playAgainEnabled,
                        action: onAgain
                    )
                }
                resultAction(t("menu"), prominent: false, action: requestLeave)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        .presentationBackground(.background)
        .preferredColorScheme(settings.sakuraLook.colorScheme)
        .alert(t("gc_leave_title"), isPresented: $confirmLeave) {
            Button(t("gc_leave_confirm"), role: .destructive, action: onMenu)
            Button(t("gc_cancel"), role: .cancel) {}
        } message: {
            Text(t("gc_leave_message"))
        }
    }

    private func requestLeave() {
        if game.mode == .gameCenter {
            confirmLeave = true
            return
        }
        onMenu()
    }

    private func resultAction(
        _ title: String,
        prominent: Bool,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
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
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var sheetDark: Bool { settings.sakuraLook == .mono }

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
        if opponentLeft {
            return t("opponent_left")
        }
        switch game.status {
        case .draw:
            return t("draw")
        case .playing:
            return ""
        case .won(let player, _):
            if case .ai = game.mode {
                return player == .red ? t("you_win") : t("you_lose")
            }
            if game.mode == .gameCenter {
                let local = gameCenter.localPlayerColor()
                return player == local ? t("you_win") : t("you_lose")
            }
            if seals == .mono {
                return player == .red ? t("black_wins") : t("white_wins")
            }
            return player == .red ? t("red_wins") : t("indigo_wins")
        }
    }

    private var subtitle: String? {
        if opponentLeft, game.status != .playing { return nil }
        if opponentWantsRematch, !localWantsRematch { return t("opponent_wants_rematch") }
        if localWantsRematch, !opponentWantsRematch { return t("waiting_for_rematch") }
        return nil
    }

    private var sheetHeight: CGFloat { subtitle == nil ? 248 : 292 }

    private var showPlayAgain: Bool { !opponentLeft }

    private var playAgainEnabled: Bool { !localWantsRematch }

    private var opponentLeft: Bool {
        game.mode == .gameCenter && gameCenter.opponentLeft()
    }

    private var localWantsRematch: Bool {
        game.mode == .gameCenter && gameCenter.localWantsRematch()
    }

    private var opponentWantsRematch: Bool {
        game.mode == .gameCenter && gameCenter.opponentWantsRematch()
    }

    private var badgeColor: Color {
        switch game.status {
        case .won(let player, _):
            Theme.seal(player, palette: seals)
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
        if isWhiteWin { return Theme.waxBlack }
        if case .draw = game.status { return Theme.waxBlack }
        return Theme.gold
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
