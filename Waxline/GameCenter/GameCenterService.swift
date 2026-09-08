import Foundation
import GameKit
import Observation
import UIKit

@Observable
final class GameCenterService: NSObject {
    var isAuthenticated = false
    var authViewController: UIViewController?
    var matchmakerPresented = false
    var activeMatch: GKTurnBasedMatch?
    var lastErrorMessage: String?
    var incomingMatch: GKTurnBasedMatch?
    var matchRevision = 0

    var localDisplayName: String {
        GKLocalPlayer.local.isAuthenticated ? GKLocalPlayer.local.displayName : ""
    }

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            if let viewController {
                self.authViewController = viewController
                return
            }
            self.authViewController = nil
            self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            if self.isAuthenticated {
                GKLocalPlayer.local.register(self)
            }
            if let error {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func presentMatchmaker() {
        guard isAuthenticated else {
            authenticate()
            return
        }
        if matchmakerPresented { return }
        matchmakerPresented = true
        GKTurnBasedMatch.loadMatches { [weak self] matches, _ in
            let hasExisting = !(matches ?? []).isEmpty
            DispatchQueue.main.async {
                self?.presentMatchmaker(showingExisting: hasExisting)
            }
        }
    }

    private func presentMatchmaker(showingExisting: Bool) {
        guard matchmakerPresented else { return }
        guard topViewController() is GKTurnBasedMatchmakerViewController == false else { return }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.defaultNumberOfPlayers = 2
        let controller = GKTurnBasedMatchmakerViewController(matchRequest: request)
        controller.turnBasedMatchmakerDelegate = self
        controller.showExistingMatches = showingExisting
        topViewController()?.present(controller, animated: true)
    }

    func attach(match: GKTurnBasedMatch) {
        activeMatch = match
        if matchmakerPresented {
            matchmakerPresented = false
            dismissMatchmakerIfNeeded()
        }
    }

    func localPlayerColor(in match: GKTurnBasedMatch) -> Player {
        let localID = GKLocalPlayer.local.gamePlayerID
        if let index = match.participants.firstIndex(where: { $0.player?.gamePlayerID == localID }) {
            return index == 0 ? .red : .indigo
        }
        return .red
    }

    func isLocalTurn(_ match: GKTurnBasedMatch) -> Bool {
        match.currentParticipant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
    }

    func model(from match: GKTurnBasedMatch) -> BoardModel {
        if let data = match.matchData, let snapshot = MatchSnapshot.decode(data) {
            return snapshot.toModel()
        }
        return .empty()
    }

    func submitTurn(match: GKTurnBasedMatch, model: BoardModel) async {
        let data = MatchSnapshot.from(model).encoded()
        switch model.status {
        case .playing:
            let next = match.participants.filter { $0 !== match.currentParticipant }
            do {
                try await match.endTurn(
                    withNextParticipants: next.isEmpty ? match.participants : next,
                    turnTimeout: 24 * 60 * 60,
                    match: data
                )
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        case .won(let player, _):
            await end(match: match, data: data, winner: player)
        case .draw:
            await end(match: match, data: data, winner: nil)
        }
        activeMatch = match
    }

    private func end(match: GKTurnBasedMatch, data: Data, winner: Player?) async {
        let redWon = winner == .red
        let indigoWon = winner == .indigo
        for (index, participant) in match.participants.enumerated() {
            if winner == nil {
                participant.matchOutcome = .tied
            } else if index == 0 {
                participant.matchOutcome = redWon ? .won : .lost
            } else {
                participant.matchOutcome = indigoWon ? .won : .lost
            }
        }
        do {
            try await match.endMatchInTurn(withMatch: data)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private func dismissMatchmakerIfNeeded() {
        guard topViewController() is GKTurnBasedMatchmakerViewController else { return }
        topViewController()?.dismiss(animated: false)
    }
}

extension GameCenterService: GKTurnBasedMatchmakerViewControllerDelegate {
    func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
        viewController.dismiss(animated: true) { [weak self] in
            self?.matchmakerPresented = false
        }
    }

    func turnBasedMatchmakerViewController(
        _ viewController: GKTurnBasedMatchmakerViewController,
        didFailWithError error: Error
    ) {
        lastErrorMessage = error.localizedDescription
        viewController.dismiss(animated: true) { [weak self] in
            self?.matchmakerPresented = false
        }
    }
}

extension GameCenterService: GKLocalPlayerListener {
    func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        if didBecomeActive {
            matchmakerPresented = false
        }
        if didBecomeActive || activeMatch?.matchID == match.matchID {
            incomingMatch = match
            activeMatch = match
            matchRevision += 1
        }
    }

    func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        if activeMatch?.matchID == match.matchID {
            incomingMatch = match
            activeMatch = match
            matchRevision += 1
        }
    }
}
