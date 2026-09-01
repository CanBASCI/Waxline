import GameKit
import SwiftUI

enum Theme {
    static let cream = Color(red: 0.96, green: 0.91, blue: 0.82)
    static let creamDeep = Color(red: 0.90, green: 0.82, blue: 0.68)
    static let ink = Color(red: 0.24, green: 0.16, blue: 0.12)
    static let waxRed = Color(red: 0.69, green: 0.13, blue: 0.18)
    static let waxIndigo = Color(red: 0.18, green: 0.16, blue: 0.42)
    static let gold = Color(red: 0.72, green: 0.55, blue: 0.28)
}

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter
    @State private var game: GameState?
    @State private var showSettings = false
    @State private var showOnboarding = false

    var body: some View {
        @Bindable var gameCenter = gameCenter
        ZStack {
            Theme.cream.ignoresSafeArea()
            if let game {
                GameView(game: game, onExit: { self.game = nil })
            } else {
                MenuView(
                    onLocal: { start(.local) },
                    onAI: { start(.ai(settings.aiLevel)) },
                    onGameCenter: { gameCenter.presentMatchmaker() },
                    onSettings: { showSettings = true },
                    onHowToPlay: { showOnboarding = true }
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
        game = GameState(mode: mode)
    }

    private func authenticateIfNeeded() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        gameCenter.authenticate()
    }

    private func openGameCenter(_ match: GKTurnBasedMatch) {
        gameCenter.attach(match: match)
        game = GameState(mode: .gameCenter, model: gameCenter.model(from: match))
    }
}
