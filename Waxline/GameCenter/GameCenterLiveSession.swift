import Foundation
import GameKit

extension GameCenterService {
    func attachLive(_ match: GKMatch) {
        if let previous = liveMatch, previous !== match {
            previous.delegate = nil
            previous.disconnect()
        }
        incomingMatch = nil
        resetSessionFlags()
        liveBoard = .empty(starting: MatchSeating.starter(forHand: 0))
        liveMatch = match
        match.delegate = self
        didAnnounceLive = false
        tryStartLiveGameIfReady()
    }

    func tryStartLiveGameIfReady() {
        guard let match = liveMatch, !match.players.isEmpty else { return }
        assignLiveColors(from: match)
        guard !didAnnounceLive else { return }
        didAnnounceLive = true
        liveSessionID = UUID().uuidString
    }

    func submitLive(_ model: BoardModel) async {
        liveBoard = model
        guard let match = liveMatch else { return }
        let data = encodedSnapshot(of: model)
        do {
            try match.sendData(toAllPlayers: data, with: .reliable)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func leaveLive(_ model: BoardModel) async {
        didLeaveLocally = true
        leftBy = liveLocalColor
        liveBoard = model
        if let match = liveMatch {
            let data = encodedSnapshot(of: model)
            try? match.sendData(toAllPlayers: data, with: .reliable)
            match.delegate = nil
            match.disconnect()
        }
        liveMatch = nil
        liveSessionID = nil
        liveInviterID = nil
        didAnnounceLive = false
    }

    func applyLiveSnapshot(_ data: Data) {
        guard let snapshot = MatchSnapshot.decode(data) else { return }
        rematchRed = snapshot.wantsRematchRed
        rematchIndigo = snapshot.wantsRematchIndigo
        matchHandIndex = snapshot.resolvedHandIndex
        if let inviterID = snapshot.inviterID, !inviterID.isEmpty {
            liveInviterID = inviterID
        }
        if leftBy == nil {
            leftBy = snapshot.departed
        }
        if let match = liveMatch {
            assignLiveColors(from: match)
        }
        liveBoard = snapshot.toModel()
        matchRevision += 1
    }

    private func assignLiveColors(from match: GKMatch) {
        if let inviterID = liveInviterID, !inviterID.isEmpty {
            liveLocalColor = MatchSeating.color(
                localID: GKLocalPlayer.local.gamePlayerID,
                inviterID: inviterID
            )
            return
        }
        let ids = ([GKLocalPlayer.local.gamePlayerID] + match.players.map(\.gamePlayerID)).sorted()
        liveLocalColor = ids.first == GKLocalPlayer.local.gamePlayerID ? .red : .indigo
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
