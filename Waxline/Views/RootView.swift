import GameKit
import SwiftUI

enum Theme {
    static let cream = Color(red: 0.96, green: 0.91, blue: 0.82)
    static let ink = Color(red: 0.24, green: 0.16, blue: 0.12)
    static let waxRed = Color(red: 0.69, green: 0.13, blue: 0.18)
    static let waxCinnabar = Color(red: 0.76, green: 0.16, blue: 0.18)
    static let waxDusk = Color(red: 0.29, green: 0.25, blue: 0.42)
    static let gold = Color(red: 0.95, green: 0.82, blue: 0.45)
    static let waxBlack = Color(red: 0.10, green: 0.09, blue: 0.08)
    static let waxWhite = Color(red: 0.95, green: 0.95, blue: 0.96)

    static let waxMagenta = Color(red: 0.95, green: 0.18, blue: 0.58)
    static let waxCyan = Color(red: 0.18, green: 0.82, blue: 0.96)
    static let waxNavy = Color(red: 0.05, green: 0.07, blue: 0.16)

    static func ink(dark: Bool) -> Color {
        dark ? Color(red: 0.93, green: 0.88, blue: 0.80) : ink
    }

    static func chipFill(dark: Bool) -> Color {
        dark ? Color(red: 0.18, green: 0.15, blue: 0.12) : cream.opacity(0.94)
    }

    static func seal(_ player: Player, palette: SealPalette) -> Color {
        switch (palette, player) {
        case (.classic, .red): waxCinnabar
        case (.classic, .indigo): waxDusk
        case (.mono, .red): waxBlack
        case (.mono, .indigo): waxWhite
        case (.neon, .red): waxMagenta
        case (.neon, .indigo): waxCyan
        }
    }
}

extension SakuraLook {
    var colorScheme: ColorScheme {
        self == .color ? .light : .dark
    }
}

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(\.scenePhase) private var scenePhase
    @State private var game: GameState?
    @State private var sessionSeries = MatchSeries()
    @State private var showSettings = false
    @State private var showOnboarding = false
    @State private var showMoreApps = false
    @State private var menuIntro = MenuIntroPlayback()
    @State private var showInvites = false
    @State private var openMatchID: String?
    @State private var pendingInviteMatch: GKTurnBasedMatch?
    @State private var confirmSwitchInvite = false
    @State private var showInviteUnavailable = false
    @State private var isJoiningMatch = false

    var body: some View {
        @Bindable var gameCenter = gameCenter
        let menuForeground = game == nil
            && !showOnboarding
            && !showSettings
            && !showMoreApps
            && !gameCenter.matchmakerPresented
        ZStack {
            if let game {
                GameView(
                    game: game,
                    onExit: {
                        sessionSeries = MatchSeries()
                        openMatchID = nil
                        self.game = nil
                    },
                    onPreserveSeries: { sessionSeries = game.series }
                )
                .id(gameCenter.sessionKey)
            } else {
                MenuView(
                    playback: menuIntro,
                    onAI: { start(.ai(settings.aiLevel)) },
                    onGameCenter: { openMultiplayer() },
                    onSettings: { showSettings = true },
                    onHowToPlay: { showOnboarding = true },
                    onMoreApps: { showMoreApps = true }
                )
            }
        }
        .overlay {
            if isJoiningMatch {
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                    ProgressView(t("gc_joining"))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .allowsHitTesting(true)
            }
        }
        .onAppear {
            menuIntro.setSoundEnabled(settings.soundEnabled)
            menuIntro.setMenuVisible(menuForeground)
        }
        .onChange(of: menuForeground) { _, visible in
            menuIntro.setMenuVisible(visible)
        }
        .onChange(of: settings.soundEnabled) { _, enabled in
            menuIntro.setSoundEnabled(enabled)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .preferredColorScheme(settings.sakuraLook.colorScheme)
        }
        .sheet(isPresented: $showMoreApps) {
            MoreAppsSheet()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                settings.hasCompletedOnboarding = true
                showOnboarding = false
                authenticateIfNeeded()
            }
            .preferredColorScheme(settings.sakuraLook.colorScheme)
        }
        .sheet(isPresented: $showInvites) {
            GameCenterInviteList(
                onSelect: { invite in
                    requestIncomingMatch(invite.match)
                },
                onNewMatch: {
                    showInvites = false
                    gameCenter.presentMatchmaker()
                }
            )
            .preferredColorScheme(settings.sakuraLook.colorScheme)
        }
        .background {
            if let controller = gameCenter.authViewController {
                GameCenterAuthPresenter(viewController: controller)
                    .frame(width: 0, height: 0)
            }
        }
        .onAppear {
            if !settings.hasCompletedOnboarding {
                showOnboarding = true
            } else {
                authenticateIfNeeded()
            }
        }
        .onChange(of: gameCenter.incomingMatch?.matchID) { _, _ in
            guard let match = gameCenter.incomingMatch, match.status != .ended else { return }
            requestIncomingMatch(match)
        }
        .onChange(of: gameCenter.liveSessionID) { _, id in
            guard id != nil else { return }
            joinLiveMatch()
        }
        .onChange(of: game == nil) { _, atMenu in
            if atMenu {
                Task { await gameCenter.refreshPendingInvites() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            menuIntro.handleScenePhase(phase)
            if phase == .active {
                Task { await gameCenter.refreshPendingInvites() }
            }
        }
        .alert(t("gc_switch_title"), isPresented: $confirmSwitchInvite) {
            Button(t("gc_switch_confirm"), role: .destructive) {
                if let match = pendingInviteMatch {
                    pendingInviteMatch = nil
                    joinIncomingMatch(match)
                }
            }
            Button(t("gc_cancel"), role: .cancel) {
                pendingInviteMatch = nil
            }
        } message: {
            Text(switchInviteMessage)
        }
        .alert(t("gc_invite_declined_title"), isPresented: $showInviteUnavailable) {
            Button(t("gc_invite_declined_ok"), role: .cancel) {}
        } message: {
            Text(t("gc_invite_declined_message"))
        }
        .alert(t("gc_error_title"), isPresented: gcErrorPresented) {
            Button(t("gc_invite_declined_ok"), role: .cancel) {
                gameCenter.lastErrorMessage = nil
            }
        } message: {
            Text(gameCenter.lastErrorMessage ?? "")
        }
    }

    private var gcErrorPresented: Binding<Bool> {
        Binding(
            get: { gameCenter.lastErrorMessage != nil },
            set: { if !$0 { gameCenter.lastErrorMessage = nil } }
        )
    }

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    private var switchInviteMessage: String {
        let name = pendingInviteMatch.map { GameCenterInvite.inviterName(in: $0) } ?? ""
        if name.isEmpty {
            return t("gc_switch_message")
        }
        return "\(name)\n\n\(t("gc_switch_message"))"
    }

    private func openMultiplayer() {
        Task {
            await gameCenter.refreshPendingInvites()
            if gameCenter.pendingInviteCount > 0 {
                showInvites = true
            } else {
                gameCenter.presentMatchmaker()
            }
        }
    }

    private func start(_ mode: GameMode) {
        menuIntro.setMenuVisible(false)
        openMatchID = nil
        game = GameState(mode: mode)
    }

    private func authenticateIfNeeded() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        gameCenter.authenticate()
    }

    private func requestIncomingMatch(_ match: GKTurnBasedMatch) {
        gameCenter.incomingMatch = nil
        gameCenter.matchmakerPresented = false
        showInvites = false
        if openMatchID == match.matchID {
            return
        }
        if game?.mode == .gameCenter {
            pendingInviteMatch = match
            confirmSwitchInvite = true
            return
        }
        joinIncomingMatch(match)
    }

    private func joinIncomingMatch(_ match: GKTurnBasedMatch) {
        gameCenter.incomingMatch = nil
        gameCenter.matchmakerPresented = false
        showInvites = false
        if openMatchID == match.matchID {
            return
        }
        Task {
            isJoiningMatch = true
            if let current = game, current.mode == .gameCenter {
                await gameCenter.leave(currentModel: current.model)
            }
            guard let live = await gameCenter.joinMatch(match) else {
                isJoiningMatch = false
                openMatchID = nil
                showInviteUnavailable = true
                return
            }
            sessionSeries = MatchSeries()
            menuIntro.setMenuVisible(false)
            openMatchID = live.matchID
            game = GameState(
                mode: .gameCenter,
                model: gameCenter.model(from: live),
                series: sessionSeries
            )
            isJoiningMatch = false
        }
    }

    private func joinLiveMatch() {
        guard let session = gameCenter.liveSessionID else { return }
        showInvites = false
        gameCenter.matchmakerPresented = false
        if openMatchID == session { return }
        Task {
            isJoiningMatch = true
            if let current = game, current.mode == .gameCenter, gameCenter.activeMatch != nil {
                await gameCenter.leave(currentModel: current.model)
            }
            sessionSeries = MatchSeries()
            menuIntro.setMenuVisible(false)
            openMatchID = session
            game = GameState(
                mode: .gameCenter,
                model: gameCenter.boardModel(),
                series: sessionSeries
            )
            isJoiningMatch = false
        }
    }
}
