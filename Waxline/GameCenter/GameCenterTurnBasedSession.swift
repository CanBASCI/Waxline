import Foundation
import GameKit

extension GameCenterService {
    func attach(match: GKTurnBasedMatch) {
        resetSessionFlags()
        pendingInvites.removeAll { $0.id == match.matchID }
        ingest(match)
        if matchmakerPresented {
            matchmakerPresented = false
            dismissMatchmakerIfNeeded()
        }
    }

    func localWantsRematch(in match: GKTurnBasedMatch) -> Bool {
        localPlayerColor(in: match) == .red ? rematchRed : rematchIndigo
    }

    func opponentWantsRematch(in match: GKTurnBasedMatch) -> Bool {
        localPlayerColor(in: match) == .red ? rematchIndigo : rematchRed
    }

    func opponentLeft(in match: GKTurnBasedMatch) -> Bool {
        guard let leftBy else { return match.status == .ended && !didLeaveLocally }
        return leftBy != localPlayerColor(in: match)
    }

    func localPlayerColor(in match: GKTurnBasedMatch) -> Player {
        let localID = GKLocalPlayer.local.gamePlayerID
        if let index = match.participants.firstIndex(where: { $0.player?.gamePlayerID == localID }) {
            return index == 0 ? .red : .indigo
        }
        return .red
    }

    func isWaitingForOpponent(in match: GKTurnBasedMatch) -> Bool {
        let localID = GKLocalPlayer.local.gamePlayerID
        if match.participants.contains(where: { $0.player?.gamePlayerID == localID && $0.status == .invited }) {
            return false
        }
        if match.status == .matching { return true }
        return match.participants.contains {
            $0.player?.gamePlayerID != localID
                && ($0.status == .invited || $0.status == .matching || $0.player == nil)
        }
    }

    func isLocalTurn(_ match: GKTurnBasedMatch) -> Bool {
        match.currentParticipant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
    }

    func isAbandonedInvite(_ match: GKTurnBasedMatch) -> Bool {
        if match.status == .ended { return true }
        if match.participants.contains(where: { $0.status == .done || $0.matchOutcome != .none }) {
            return true
        }
        if let data = match.matchData, let snapshot = MatchSnapshot.decode(data), snapshot.departed != nil {
            return true
        }
        return false
    }

    func inviteWasDeclined(in match: GKTurnBasedMatch) -> Bool {
        guard !didLeaveLocally else { return false }
        if isWaitingForOpponent(in: match) { return false }
        guard model(from: match).isFreshDeal else { return false }
        let localID = GKLocalPlayer.local.gamePlayerID
        let localIsInvitee = match.participants.contains {
            $0.player?.gamePlayerID == localID && $0.status == .invited
        }
        if !localIsInvitee {
            return match.status == .ended
                || match.participants.contains {
                    $0.player?.gamePlayerID != localID
                        && ($0.status == .done || $0.matchOutcome != .none)
                }
        }
        return isAbandonedInvite(match)
    }

    func pulseWaitingHeartbeat(suspended _: Bool? = nil) async {
        guard liveMatch == nil else { return }
        guard activeMatch != nil else { return }
        await refreshActiveMatch()
    }

    func model(from match: GKTurnBasedMatch) -> BoardModel {
        if let data = match.matchData, let snapshot = MatchSnapshot.decode(data) {
            return snapshot.toModel()
        }
        return .empty()
    }

    func leaveTurnBased(_ currentModel: BoardModel) async {
        guard let match = await refreshedMatch() else { return }
        if didLeaveLocally || match.status == .ended {
            didLeaveLocally = true
            incomingMatch = nil
            dropInvite(match.matchID)
            activeMatch = nil
            await refreshPendingInvites()
            return
        }
        didLeaveLocally = true
        leftBy = localPlayerColor(in: match)
        incomingMatch = nil
        dropInvite(match.matchID)
        let data = encoded(currentModel)
        applyLeaveOutcomes(on: match, model: currentModel)
        do {
            if isLocalTurn(match) {
                try await match.endMatchInTurn(withMatch: data)
            } else {
                try await sendExchange(data, on: match)
                try await match.participantQuitOutOfTurn(with: .quit)
            }
        } catch {
            do {
                try await match.participantQuitOutOfTurn(with: .quit)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
        try? await match.remove()
        activeMatch = nil
        await refreshPendingInvites()
        matchRevision += 1
    }

    func commitRematch(on match: GKTurnBasedMatch) async {
        rematchRed = false
        rematchIndigo = false
        leftBy = nil
        let deal = nextRematchDeal()
        await publish(deal, on: match, advanceTurn: true, to: deal.currentPlayer)
    }

    func ingest(_ match: GKTurnBasedMatch) {
        activeMatch = match
        guard let data = match.matchData, let snapshot = MatchSnapshot.decode(data) else { return }
        rematchRed = snapshot.wantsRematchRed
        rematchIndigo = snapshot.wantsRematchIndigo
        leftBy = snapshot.departed
        matchHandIndex = snapshot.resolvedHandIndex
    }

    func encoded(_ model: BoardModel) -> Data {
        encodedSnapshot(of: model)
    }

    func refreshedMatch() async -> GKTurnBasedMatch? {
        guard let current = activeMatch else { return nil }
        do {
            let latest = try await GKTurnBasedMatch.load(withID: current.matchID)
            ingest(latest)
            return latest
        } catch {
            ingest(current)
            return current
        }
    }

    func publish(
        _ model: BoardModel,
        on match: GKTurnBasedMatch,
        advanceTurn: Bool,
        to player: Player? = nil
    ) async {
        let data = encoded(model)
        do {
            if advanceTurn, isLocalTurn(match) {
                let next = nextParticipants(on: match, preferring: player)
                if let target = next.first, match.currentParticipant === target {
                    try await match.saveCurrentTurn(withMatch: data)
                } else {
                    try await match.endTurn(
                        withNextParticipants: next,
                        turnTimeout: 24 * 60 * 60,
                        match: data
                    )
                }
            } else if isLocalTurn(match) {
                try await match.saveCurrentTurn(withMatch: data)
            } else {
                try await sendExchange(data, on: match)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        activeMatch = match
    }

    func nextParticipants(on match: GKTurnBasedMatch, preferring player: Player?) -> [GKTurnBasedParticipant] {
        if let player {
            let index = player == .red ? 0 : 1
            if match.participants.indices.contains(index) {
                return [match.participants[index]]
            }
        }
        let others = match.participants.filter { $0 !== match.currentParticipant }
        return others.isEmpty ? match.participants : others
    }

    func sendExchange(_ data: Data, on match: GKTurnBasedMatch) async throws {
        let others = match.participants.filter {
            $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID
        }
        guard !others.isEmpty else { return }
        _ = try await match.sendExchange(
            to: others,
            data: data,
            localizableMessageKey: "play_again",
            arguments: [],
            timeout: 24 * 60 * 60
        )
    }

    func applyLeaveOutcomes(on match: GKTurnBasedMatch, model: BoardModel) {
        let local = localPlayerColor(in: match)
        for (index, participant) in match.participants.enumerated() {
            let player: Player = index == 0 ? .red : .indigo
            if model.status != .playing {
                switch model.status {
                case .draw:
                    participant.matchOutcome = .tied
                case .won(let winner, _):
                    participant.matchOutcome = winner == player ? .won : .lost
                case .playing:
                    break
                }
            } else {
                participant.matchOutcome = player == local ? .quit : .won
            }
        }
    }

    func mergeExchange(_ data: Data, on match: GKTurnBasedMatch) async {
        guard let snapshot = MatchSnapshot.decode(data) else { return }
        rematchRed = snapshot.wantsRematchRed || rematchRed
        rematchIndigo = snapshot.wantsRematchIndigo || rematchIndigo
        if leftBy == nil {
            leftBy = snapshot.departed
        }
        if isLocalTurn(match) {
            if bothWantRematch {
                await commitRematch(on: match)
            } else {
                let model = snapshot.toModel()
                await publish(model, on: match, advanceTurn: false)
            }
        }
    }
}
