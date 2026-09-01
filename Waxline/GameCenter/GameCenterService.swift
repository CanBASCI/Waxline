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
        matchmakerPresented = true
    }

    func attach(match: GKTurnBasedMatch) {
        activeMatch = match
        matchmakerPresented = false
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
}

extension GameCenterService: GKLocalPlayerListener {
    func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
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
