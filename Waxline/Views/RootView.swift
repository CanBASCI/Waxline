import GameKit
import SwiftUI

enum Theme {
    static let cream = Color(red: 0.96, green: 0.91, blue: 0.82)
    static let creamDeep = Color(red: 0.90, green: 0.82, blue: 0.68)
    static let ink = Color(red: 0.24, green: 0.16, blue: 0.12)
    static let waxRed = Color(red: 0.69, green: 0.13, blue: 0.18)
    static let waxIndigo = Color(red: 0.18, green: 0.16, blue: 0.42)
    static let gold = Color(red: 0.95, green: 0.82, blue: 0.45)
    static let waxBlack = Color(red: 0.10, green: 0.09, blue: 0.08)
    static let waxWhite = Color(red: 0.95, green: 0.95, blue: 0.96)

    static func canvas(dark: Bool) -> Color {
        dark ? Color(red: 0.10, green: 0.08, blue: 0.07) : cream
    }

    static func ink(dark: Bool) -> Color {
        dark ? Color(red: 0.93, green: 0.88, blue: 0.80) : ink
    }

    static func chipFill(dark: Bool) -> Color {
        dark ? Color(red: 0.18, green: 0.15, blue: 0.12) : cream.opacity(0.94)
    }

    static func seal(_ player: Player, palette: SealPalette) -> Color {
        switch (palette, player) {
        case (.classic, .red): waxRed
        case (.classic, .indigo): waxIndigo
        case (.mono, .red): waxBlack
        case (.mono, .indigo): waxWhite
        }
    }
}

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter
    @State private var game: GameState?
    @State private var showSettings = false
    @State private var showOnboarding = false
    @State private var menuIntro = MenuIntroPlayback()

    var body: some View {
        @Bindable var gameCenter = gameCenter
        let menuForeground = game == nil
            && !showOnboarding
            && !showSettings
            && !gameCenter.matchmakerPresented
        ZStack {
            if let game {
                Theme.cream.ignoresSafeArea()
                GameView(game: game, onExit: { self.game = nil })
            } else {
                MenuView(
                    playback: menuIntro,
                    onLocal: { start(.local) },
                    onAI: { start(.ai(settings.aiLevel)) },
                    onGameCenter: { gameCenter.presentMatchmaker() },
                    onSettings: { showSettings = true },
                    onHowToPlay: { showOnboarding = true }
                )
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
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                settings.hasCompletedOnboarding = true
                showOnboarding = false
                authenticateIfNeeded()
            }
        }
        .fullScreenCover(isPresented: $gameCenter.matchmakerPresented) {
            TurnBasedMatchmakerView(
                onMatch: { match in
                    openGameCenter(match)
                },
                onCancel: { gameCenter.matchmakerPresented = false }
            )
            .ignoresSafeArea()
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
            if let match = gameCenter.incomingMatch, game == nil {
                gameCenter.incomingMatch = nil
                gameCenter.matchmakerPresented = false
                openGameCenter(match)
            }
        }
    }

    private func start(_ mode: GameMode) {
        menuIntro.setMenuVisible(false)
        game = GameState(mode: mode)
    }

    private func authenticateIfNeeded() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        gameCenter.authenticate()
    }

    private func openGameCenter(_ match: GKTurnBasedMatch) {
        menuIntro.setMenuVisible(false)
        gameCenter.attach(match: match)
        game = GameState(mode: .gameCenter, model: gameCenter.model(from: match))
    }
}
