import Foundation
import GameKit
import UIKit

extension GameCenterService {
    func refreshPendingInvites() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            GKTurnBasedMatch.loadMatches { [weak self] matches, _ in
                let invites = (matches ?? []).compactMap(GameCenterInvite.make)
                DispatchQueue.main.async {
                    self?.pendingInvites = invites
                    continuation.resume()
                }
            }
        }
    }

    func joinMatch(_ match: GKTurnBasedMatch) async -> GKTurnBasedMatch? {
        let live: GKTurnBasedMatch
        do {
            live = try await GKTurnBasedMatch.load(withID: match.matchID)
        } catch {
            dropInvite(match.matchID)
            return nil
        }
        if isAbandonedInvite(live) {
            if live.status == .ended {
                await discardStaleInvite(live)
            }
            return nil
        }
        let localID = GKLocalPlayer.local.gamePlayerID
        if live.participants.contains(where: { $0.player?.gamePlayerID == localID && $0.status == .invited }) {
            do {
                try await live.acceptInvite()
            } catch {
                let again = (try? await GKTurnBasedMatch.load(withID: live.matchID)) ?? live
                if again.status == .ended
                    || again.participants.contains(where: { $0.matchOutcome != .none }) {
                    await discardStaleInvite(again)
                    return nil
                }
                if again.participants.contains(where: { $0.player?.gamePlayerID == localID && $0.status == .invited }) {
                    return nil
                }
            }
        }
        let accepted = (try? await GKTurnBasedMatch.load(withID: live.matchID)) ?? live
        if accepted.status == .ended {
            await discardStaleInvite(accepted)
            return nil
        }
        attach(match: accepted)
        return accepted
    }

    func declineInvite(_ invite: GameCenterInvite) async {
        dropInvite(invite.id)
        await finishDeclining(invite)
    }

    func deletePendingInvites(at offsets: IndexSet) {
        let invites = offsets.compactMap { pendingInvites.indices.contains($0) ? pendingInvites[$0] : nil }
        for index in offsets.sorted(by: >) where pendingInvites.indices.contains(index) {
            pendingInvites.remove(at: index)
        }
        Task {
            for invite in invites {
                await finishDeclining(invite)
            }
        }
    }

    func presentMatchmaker() {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.defaultNumberOfPlayers = 2
        request.inviteMessage = String(localized: "gc_invite_message")
        presentMatchmaker(for: request)
    }

    func handleInvite(_ invite: GKInvite) {
        guard isAuthenticated else {
            pendingGKInvite = invite
            authenticate()
            return
        }
        matchmakerPresented = true
        guard let controller = GKMatchmakerViewController(invite: invite) else {
            matchmakerPresented = false
            return
        }
        controller.matchmakerDelegate = self
        DispatchQueue.main.async { [weak self] in
            self?.topViewController()?.present(controller, animated: true)
        }
    }

    func presentMatchmaker(for request: GKMatchRequest) {
        guard isAuthenticated else {
            authenticate()
            return
        }
        if matchmakerPresented { return }
        if topViewController() is GKMatchmakerViewController { return }
        matchmakerPresented = true
        guard let controller = GKMatchmakerViewController(matchRequest: request) else {
            matchmakerPresented = false
            lastErrorMessage = String(localized: "gc_error_title")
            return
        }
        controller.matchmakerDelegate = self
        guard let top = topViewController() else {
            matchmakerPresented = false
            return
        }
        top.present(controller, animated: true)
    }

    func finishDeclining(_ invite: GameCenterInvite) async {
        let match = invite.match
        let localID = GKLocalPlayer.local.gamePlayerID
        let invited = match.participants.contains {
            $0.player?.gamePlayerID == localID && $0.status == .invited
        }
        do {
            if invited {
                try await match.declineInvite()
            } else if isLocalTurn(match) {
                applyLeaveOutcomes(on: match, model: model(from: match))
                try await match.endMatchInTurn(withMatch: match.matchData ?? Data())
            } else {
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
        await refreshPendingInvites()
    }

    func discardStaleInvite(_ match: GKTurnBasedMatch) async {
        dropInvite(match.matchID)
        let localID = GKLocalPlayer.local.gamePlayerID
        if match.participants.contains(where: { $0.player?.gamePlayerID == localID && $0.status == .invited }) {
            try? await match.declineInvite()
        }
        try? await match.remove()
    }

    func dismissMatchmakerIfNeeded() {
        guard topViewController() is GKMatchmakerViewController else { return }
        topViewController()?.dismiss(animated: false)
    }
}

extension GameCenterService: GKMatchmakerViewControllerDelegate {
    func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        viewController.dismiss(animated: true) { [weak self] in
            self?.matchmakerPresented = false
        }
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        lastErrorMessage = error.localizedDescription
        viewController.dismiss(animated: true) { [weak self] in
            self?.matchmakerPresented = false
        }
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        viewController.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.matchmakerPresented = false
            self.attachLive(match)
        }
    }
}

extension GameCenterService: GKLocalPlayerListener {
    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        DispatchQueue.main.async { [weak self] in
            self?.handleInvite(invite)
        }
    }

    func player(_ player: GKPlayer, didRequestMatchWithRecipients recipientPlayers: [GKPlayer]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let request = GKMatchRequest()
            request.minPlayers = 2
            request.maxPlayers = 2
            request.recipients = recipientPlayers
            request.inviteMessage = String(localized: "gc_invite_message")
            self.presentMatchmaker(for: request)
        }
    }

    func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        if liveMatch != nil {
            Task { await refreshPendingInvites() }
            return
        }
        if match.status == .ended || match.participants.contains(where: { $0.matchOutcome != .none }) {
            dropInvite(match.matchID)
        }
        Task { await refreshPendingInvites() }
        if didBecomeActive {
            matchmakerPresented = false
            if let currentID = activeMatch?.matchID, currentID != match.matchID {
                incomingMatch = match
                return
            }
            ingest(match)
            incomingMatch = match
            matchRevision += 1
            return
        }
        if activeMatch?.matchID == match.matchID {
            ingest(match)
            matchRevision += 1
        }
    }

    func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        dropInvite(match.matchID)
        Task { await refreshPendingInvites() }
        guard match.matchID == activeMatch?.matchID else { return }
        if didLeaveLocally {
            incomingMatch = nil
            return
        }
        ingest(match)
        if leftBy == nil {
            leftBy = localPlayerColor(in: match).opponent
        }
        incomingMatch = match
        matchRevision += 1
    }

    func player(_ player: GKPlayer, wantsToQuitMatch match: GKTurnBasedMatch) {
        dropInvite(match.matchID)
        Task {
            if match.matchID == activeMatch?.matchID {
                ingest(match)
                if isLocalTurn(match), match.status != .ended {
                    applyLeaveOutcomes(on: match, model: model(from: match))
                    try? await match.endMatchInTurn(withMatch: encoded(model(from: match)))
                }
                matchRevision += 1
            }
            await refreshPendingInvites()
        }
    }

    func player(
        _ player: GKPlayer,
        receivedExchangeRequest exchange: GKTurnBasedExchange,
        for match: GKTurnBasedMatch
    ) {
        Task { @MainActor in
            if match.matchID == activeMatch?.matchID || activeMatch == nil {
                ingest(match)
                if let data = exchange.data {
                    await mergeExchange(data, on: match)
                }
                incomingMatch = match
                matchRevision += 1
            }
            do {
                try await exchange.reply(
                    withLocalizableMessageKey: "menu",
                    arguments: [],
                    data: Data()
                )
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }
}

nonisolated struct GameCenterInvite: Identifiable, @unchecked Sendable {
    var id: String
    var opponentName: String
    var match: GKTurnBasedMatch

    nonisolated static func make(_ match: GKTurnBasedMatch) -> GameCenterInvite? {
        guard match.status != .ended else { return nil }
        guard match.participants.allSatisfy({ $0.matchOutcome == .none }) else { return nil }
        let localID = GKLocalPlayer.local.gamePlayerID
        guard let local = match.participants.first(where: { $0.player?.gamePlayerID == localID }),
              local.status == .invited else { return nil }
        if match.participants.contains(where: { $0.status == .done }) { return nil }
        return GameCenterInvite(
            id: match.matchID,
            opponentName: inviterName(in: match),
            match: match
        )
    }

    nonisolated static func inviter(in match: GKTurnBasedMatch) -> GKPlayer? {
        let localID = GKLocalPlayer.local.gamePlayerID
        let others = match.participants.filter { $0.player?.gamePlayerID != localID }
        if let player = others.first(where: { $0.player != nil })?.player {
            return player
        }
        return match.participants.first { $0.status != .invited }?.player
    }

    nonisolated static func inviterName(in match: GKTurnBasedMatch) -> String {
        if let name = inviter(in: match)?.displayName, !name.isEmpty {
            return name
        }
        return String(localized: "gc_unknown_player")
    }

    func loadPhoto() async -> UIImage? {
        guard let player = Self.inviter(in: match) else { return nil }
        return try? await player.loadPhoto(for: .small)
    }
}
