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
    var rematchRed = false
    var rematchIndigo = false
    var leftBy: Player?
    var pendingInvites: [GameCenterInvite] = []
    var liveSessionID: String?
    private var liveMatch: GKMatch?
    private var liveBoard = BoardModel.empty()
    private var liveLocalColor: Player = .red
    private var pendingGKInvite: GKInvite?
    private var didLeaveLocally = false
    private var didAnnounceLive = false
    private var waitingHeartbeat: Double?
    private var hostIsSuspended = false
    private let hostHeartbeatLimit: TimeInterval = 90
    private let hostSuspendedLimit: TimeInterval = 20 * 60

    var hasActiveSession: Bool { liveMatch != nil || activeMatch != nil }

    var sessionKey: String { liveSessionID ?? activeMatch?.matchID ?? "local" }

    func localPlayerColor() -> Player {
        if liveMatch != nil { return liveLocalColor }
        if let match = activeMatch { return localPlayerColor(in: match) }
        return .red
    }

    func isLocalTurn() -> Bool {
        if liveMatch != nil { return liveBoard.currentPlayer == liveLocalColor }
        if let match = activeMatch { return isLocalTurn(match) }
        return true
    }

    func isWaitingForOpponent() -> Bool {
        if liveMatch != nil { return false }
        if let match = activeMatch { return isWaitingForOpponent(in: match) }
        return false
    }

    func boardModel() -> BoardModel {
        if liveMatch != nil { return liveBoard }
        if let match = activeMatch { return model(from: match) }
        return .empty()
    }

    func opponentLeft() -> Bool {
        if liveMatch != nil {
            guard let leftBy else { return false }
            return leftBy != liveLocalColor
        }
        if let match = activeMatch { return opponentLeft(in: match) }
        return false
    }

    func localWantsRematch() -> Bool {
        if liveMatch != nil {
            return liveLocalColor == .red ? rematchRed : rematchIndigo
        }
        if let match = activeMatch { return localWantsRematch(in: match) }
        return false
    }

    func opponentWantsRematch() -> Bool {
        if liveMatch != nil {
            return liveLocalColor == .red ? rematchIndigo : rematchRed
        }
        if let match = activeMatch { return opponentWantsRematch(in: match) }
        return false
    }

    func inviteWasDeclined() -> Bool {
        if liveMatch != nil { return false }
        if let match = activeMatch { return inviteWasDeclined(in: match) }
        return false
    }

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
                Task { await self.refreshPendingInvites() }
                if let invite = self.pendingGKInvite {
                    self.pendingGKInvite = nil
                    self.handleInvite(invite)
                }
            }
            if let error {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    var pendingInviteCount: Int { pendingInvites.count }

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

    func openInvite(_ invite: GameCenterInvite) {
        ingest(invite.match)
        incomingMatch = invite.match
        matchRevision += 1
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

    private func presentMatchmaker(for request: GKMatchRequest) {
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

    func attach(match: GKTurnBasedMatch) {
        didLeaveLocally = false
        rematchRed = false
        rematchIndigo = false
        leftBy = nil
        waitingHeartbeat = nil
        hostIsSuspended = false
        pendingInvites.removeAll { $0.id == match.matchID }
        ingest(match)
        if isWaitingForOpponent(in: match) {
            waitingHeartbeat = Date().timeIntervalSince1970
            Task { await pulseWaitingHeartbeat() }
        }
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

    var bothWantRematch: Bool { rematchRed && rematchIndigo }

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
        if match.participants.contains(where: { $0.status == .invited || $0.status == .matching }) {
            return false
        }
        return isHostHeartbeatExpired(match)
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

    func pulseWaitingHeartbeat(suspended: Bool? = nil) async {
        guard let match = activeMatch, isLocalTurn(match) else { return }
        if let suspended {
            hostIsSuspended = suspended
        }
        waitingHeartbeat = Date().timeIntervalSince1970
        // Writing match data before the invitee accepts cancels the invitation.
        guard !isWaitingForOpponent(in: match) else { return }
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        if hostIsSuspended {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "waxline.invite-heartbeat") {
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
            }
        }
        await publish(model(from: match), on: match, advanceTurn: false)
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }

    func refreshActiveMatch() async {
        guard liveMatch == nil else { return }
        guard await refreshedMatch() != nil else { return }
        matchRevision += 1
    }

    func model(from match: GKTurnBasedMatch) -> BoardModel {
        if let data = match.matchData, let snapshot = MatchSnapshot.decode(data) {
            return snapshot.toModel()
        }
        return .empty()
    }

    func submitTurn(model: BoardModel) async {
        if liveMatch != nil {
            await submitLive(model)
            return
        }
        if let match = activeMatch {
            await publish(model, on: match, advanceTurn: true)
            activeMatch = match
        }
    }

    func submitTurn(match: GKTurnBasedMatch, model: BoardModel) async {
        await publish(model, on: match, advanceTurn: true)
        activeMatch = match
    }

    func requestRematch(currentModel: BoardModel) async {
        if liveMatch != nil {
            if liveLocalColor == .red {
                rematchRed = true
            } else {
                rematchIndigo = true
            }
            if bothWantRematch {
                rematchRed = false
                rematchIndigo = false
                leftBy = nil
                liveBoard = .empty()
                await submitLive(liveBoard)
            } else {
                await submitLive(currentModel)
            }
            matchRevision += 1
            return
        }
        guard let match = await refreshedMatch() else { return }
        let local = localPlayerColor(in: match)
        if local == .red {
            rematchRed = true
        } else {
            rematchIndigo = true
        }
        if bothWantRematch {
            await commitRematch(on: match)
        } else {
            await publish(currentModel, on: match, advanceTurn: false)
        }
        matchRevision += 1
    }

    func leave(currentModel: BoardModel) async {
        if activeMatch != nil {
            await leaveTurnBased(currentModel)
            return
        }
        if liveMatch != nil {
            await leaveLive(currentModel)
        }
    }

    private func leaveTurnBased(_ currentModel: BoardModel) async {
        guard let match = await refreshedMatch() else { return }
        if didLeaveLocally || match.status == .ended {
            didLeaveLocally = true
            incomingMatch = nil
            waitingHeartbeat = nil
            hostIsSuspended = false
            dropInvite(match.matchID)
            activeMatch = nil
            await refreshPendingInvites()
            return
        }
        didLeaveLocally = true
        leftBy = localPlayerColor(in: match)
        incomingMatch = nil
        waitingHeartbeat = nil
        hostIsSuspended = false
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

    func commitRematchIfNeeded() async {
        guard bothWantRematch, let match = activeMatch, isLocalTurn(match) else { return }
        await commitRematch(on: match)
        matchRevision += 1
    }

    private func dropInvite(_ matchID: String) {
        pendingInvites.removeAll { $0.id == matchID }
    }

    private func finishDeclining(_ invite: GameCenterInvite) async {
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

    private func commitRematch(on match: GKTurnBasedMatch) async {
        rematchRed = false
        rematchIndigo = false
        leftBy = nil
        await publish(.empty(), on: match, advanceTurn: true, toFirstPlayer: true)
    }

    private func ingest(_ match: GKTurnBasedMatch) {
        activeMatch = match
        guard let data = match.matchData, let snapshot = MatchSnapshot.decode(data) else { return }
        rematchRed = snapshot.wantsRematchRed
        rematchIndigo = snapshot.wantsRematchIndigo
        leftBy = snapshot.departed
    }

    private func encoded(_ model: BoardModel) -> Data {
        let beat: Double?
        if let match = activeMatch, isWaitingForOpponent(in: match) {
            beat = nil
        } else {
            beat = waitingHeartbeat
        }
        return MatchSnapshot.from(
            model,
            rematchRed: rematchRed,
            rematchIndigo: rematchIndigo,
            leftBy: leftBy,
            hostHeartbeat: beat,
            hostSuspended: hostIsSuspended
        ).encoded()
    }

    private func isHostHeartbeatExpired(_ match: GKTurnBasedMatch) -> Bool {
        guard let data = match.matchData,
              let snapshot = MatchSnapshot.decode(data),
              let beat = snapshot.hostHeartbeat else {
            return false
        }
        let limit = snapshot.hostSuspended == true ? hostSuspendedLimit : hostHeartbeatLimit
        return Date().timeIntervalSince1970 - beat > limit
    }

    private func discardStaleInvite(_ match: GKTurnBasedMatch) async {
        dropInvite(match.matchID)
        let localID = GKLocalPlayer.local.gamePlayerID
        if match.participants.contains(where: { $0.player?.gamePlayerID == localID && $0.status == .invited }) {
            try? await match.declineInvite()
        }
        try? await match.remove()
    }

    private func refreshedMatch() async -> GKTurnBasedMatch? {
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

    private func publish(
        _ model: BoardModel,
        on match: GKTurnBasedMatch,
        advanceTurn: Bool,
        toFirstPlayer: Bool = false
    ) async {
        let data = encoded(model)
        do {
            if advanceTurn, isLocalTurn(match) {
                let next: [GKTurnBasedParticipant]
                if toFirstPlayer, let first = match.participants.first {
                    next = [first]
                } else {
                    let others = match.participants.filter { $0 !== match.currentParticipant }
                    next = others.isEmpty ? match.participants : others
                }
                if toFirstPlayer,
                   let first = match.participants.first,
                   match.currentParticipant === first {
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

    private func sendExchange(_ data: Data, on match: GKTurnBasedMatch) async throws {
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

    private func applyLeaveOutcomes(on match: GKTurnBasedMatch, model: BoardModel) {
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

    private func mergeExchange(_ data: Data, on match: GKTurnBasedMatch) async {
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
        let top = topViewController()
        guard top is GKMatchmakerViewController || top is GKTurnBasedMatchmakerViewController else { return }
        top?.dismiss(animated: false)
    }

    private func attachLive(_ match: GKMatch) {
        if let previous = liveMatch, previous !== match {
            previous.delegate = nil
            previous.disconnect()
        }
        incomingMatch = nil
        didLeaveLocally = false
        rematchRed = false
        rematchIndigo = false
        leftBy = nil
        waitingHeartbeat = nil
        hostIsSuspended = false
        liveBoard = .empty()
        liveMatch = match
        match.delegate = self
        didAnnounceLive = false
        tryStartLiveGameIfReady()
    }

    private func tryStartLiveGameIfReady() {
        guard let match = liveMatch, !match.players.isEmpty else { return }
        assignLiveColors(from: match)
        guard !didAnnounceLive else { return }
        didAnnounceLive = true
        liveSessionID = UUID().uuidString
    }

    private func assignLiveColors(from match: GKMatch) {
        let ids = ([GKLocalPlayer.local.gamePlayerID] + match.players.map(\.gamePlayerID)).sorted()
        liveLocalColor = ids.first == GKLocalPlayer.local.gamePlayerID ? .red : .indigo
    }

    private func submitLive(_ model: BoardModel) async {
        liveBoard = model
        guard let match = liveMatch else { return }
        let data = MatchSnapshot.from(
            model,
            rematchRed: rematchRed,
            rematchIndigo: rematchIndigo,
            leftBy: leftBy
        ).encoded()
        do {
            try match.sendData(toAllPlayers: data, with: .reliable)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func leaveLive(_ model: BoardModel) async {
        didLeaveLocally = true
        leftBy = liveLocalColor
        liveBoard = model
        if let match = liveMatch {
            let data = MatchSnapshot.from(
                model,
                rematchRed: rematchRed,
                rematchIndigo: rematchIndigo,
                leftBy: leftBy
            ).encoded()
            try? match.sendData(toAllPlayers: data, with: .reliable)
            match.delegate = nil
            match.disconnect()
        }
        liveMatch = nil
        liveSessionID = nil
        didAnnounceLive = false
    }

    private func applyLiveSnapshot(_ data: Data) {
        guard let snapshot = MatchSnapshot.decode(data) else { return }
        rematchRed = snapshot.wantsRematchRed
        rematchIndigo = snapshot.wantsRematchIndigo
        if leftBy == nil {
            leftBy = snapshot.departed
        }
        liveBoard = snapshot.toModel()
        matchRevision += 1
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

extension GameCenterService: GKMatchDelegate {
    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        DispatchQueue.main.async { [weak self] in
            guard let self, match === self.liveMatch else { return }
            self.applyLiveSnapshot(data)
        }
    }

    func match(
        _ match: GKMatch,
        didReceive data: Data,
        forRecipient recipient: GKPlayer,
        fromRemotePlayer player: GKPlayer
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, match === self.liveMatch else { return }
            self.applyLiveSnapshot(data)
        }
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, match === self.liveMatch else { return }
            switch state {
            case .connected:
                self.tryStartLiveGameIfReady()
            case .disconnected:
                guard !self.didLeaveLocally else { return }
                if self.leftBy == nil {
                    self.leftBy = self.liveLocalColor.opponent
                }
                self.matchRevision += 1
            default:
                break
            }
        }
    }

    func match(_ match: GKMatch, didFailWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, match === self.liveMatch else { return }
            if let error {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

extension GameCenterService: GKLocalPlayerListener {
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
            if isWaitingForOpponent(in: match) {
                ingest(match)
                if topViewController() is GKTurnBasedMatchmakerViewController {
                    return
                }
                matchmakerPresented = false
                incomingMatch = match
                matchRevision += 1
                return
            }
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

}
