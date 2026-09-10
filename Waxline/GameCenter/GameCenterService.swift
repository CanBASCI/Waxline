import Foundation
import GameKit
import Observation
import UIKit

@Observable
final class GameCenterService: NSObject {
    var isAuthenticated = false
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
    var liveMatch: GKMatch?
    var liveBoard = BoardModel.empty()
    var liveLocalColor: Player = .red
    var liveInviterID: String?
    var matchHandIndex = 0
    var pendingGKInvite: GKInvite?
    var didLeaveLocally = false
    var didAnnounceLive = false
    var matchmakerSuppressUntil: Date?

    var hasActiveSession: Bool { liveMatch != nil || activeMatch != nil }

    var sessionKey: String { liveSessionID ?? activeMatch?.matchID ?? "local" }

    var bothWantRematch: Bool { rematchRed && rematchIndigo }

    var pendingInviteCount: Int { pendingInvites.count }

    var localDisplayName: String {
        GKLocalPlayer.local.isAuthenticated ? GKLocalPlayer.local.displayName : ""
    }

    var opponentDisplayName: String {
        if let name = opponentPlayer()?.displayName, !name.isEmpty {
            return name
        }
        return L10n.system("gc_unknown_player")
    }

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

    func opponentPlayer() -> GKPlayer? {
        if let match = liveMatch {
            return match.players.first
        }
        if let match = activeMatch {
            let localID = GKLocalPlayer.local.gamePlayerID
            return match.participants.first { $0.player?.gamePlayerID != localID }?.player
        }
        return nil
    }

    func loadOpponentPhoto() async -> UIImage? {
        guard let player = opponentPlayer() else { return nil }
        return try? await player.loadPhoto(for: .small)
    }

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            if let viewController {
                self.presentGameCenterAuth(viewController)
                return
            }
            self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            if self.isAuthenticated {
                GKLocalPlayer.local.register(self)
                Task { await self.refreshPendingInvites() }
                if let invite = self.pendingGKInvite {
                    self.pendingGKInvite = nil
                    self.handleInvite(invite)
                }
            }
            if let error, !isBenignAuthDismissal(error) {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func presentGameCenterAuth(_ controller: UIViewController) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if controller.presentingViewController != nil { return }
            guard let top = self.topViewController() else { return }
            if top === controller || top.presentedViewController === controller { return }
            top.present(controller, animated: true)
        }
    }

    func isBenignAuthDismissal(_ error: Error) -> Bool {
        if isAuthenticated && isTransientGameCenterError(error) { return true }
        return isBenignMatchmakerDismissal(error)
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
                liveBoard = nextRematchDeal()
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

    func commitRematchIfNeeded() async {
        guard bothWantRematch, let match = activeMatch, isLocalTurn(match) else { return }
        await commitRematch(on: match)
        matchRevision += 1
    }

    func refreshActiveMatch() async {
        guard liveMatch == nil else { return }
        guard await refreshedMatch() != nil else { return }
        matchRevision += 1
    }

    func dropInvite(_ matchID: String) {
        pendingInvites.removeAll { $0.id == matchID }
    }

    func resetSessionFlags() {
        didLeaveLocally = false
        rematchRed = false
        rematchIndigo = false
        leftBy = nil
        matchHandIndex = 0
    }

    func markLocalAsLiveInviter() {
        liveInviterID = GKLocalPlayer.local.gamePlayerID
    }

    func markLiveInvite(from invite: GKInvite) {
        liveInviterID = invite.sender.gamePlayerID
    }

    func nextRematchDeal() -> BoardModel {
        matchHandIndex += 1
        return .empty(starting: MatchSeating.starter(forHand: matchHandIndex))
    }

    func encodedSnapshot(of model: BoardModel) -> Data {
        MatchSnapshot.from(
            model,
            rematchRed: rematchRed,
            rematchIndigo: rematchIndigo,
            leftBy: leftBy,
            handIndex: matchHandIndex,
            inviterID: liveInviterID
        ).encoded()
    }

    func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    func isTransientGameCenterError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCancelled, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
                return true
            default:
                break
            }
        }
        return false
    }

    func isBenignMatchmakerDismissal(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == "ExtensionErrorDomain", ns.code == -5900 { return true }
        if ns.domain == GKErrorDomain, ns.code == GKError.Code.cancelled.rawValue { return true }
        return isTransientGameCenterError(error)
    }
}
