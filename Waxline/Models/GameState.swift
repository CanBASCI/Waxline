import Foundation
import Observation

@Observable
final class GameState {
    private(set) var model: BoardModel
    let mode: GameMode

    init(mode: GameMode, model: BoardModel = .empty()) {
        self.mode = mode
        self.model = model
    }

    var cells: [[Cell]] { model.cells }
    var currentPlayer: Player { model.currentPlayer }
    var phase: TurnPhase { model.phase }
    var status: GameStatus { model.status }
    var lastPlacement: Position? { model.lastPlacement }
    var isFinished: Bool { model.status != .playing }
    private(set) var moveLog: [LastMove] = []
    private var pendingPlace: (Player, Position)?

    var localHumanPlayer: Player? {
        switch mode {
        case .local, .gameCenter: nil
        case .ai: .red
        }
    }

    func place(at position: Position) -> Bool {
        let player = model.currentPlayer
        guard model.place(at: position) else { return false }
        if model.status != .playing {
            recordMove(LastMove(player: player, position: position, quadrant: nil, clockwise: nil))
            pendingPlace = nil
        } else {
            pendingPlace = (player, position)
        }
        return true
    }

    func rotate(quadrant: Quadrant, clockwise: Bool) -> Bool {
        guard model.rotate(quadrant: quadrant, clockwise: clockwise) else { return false }
        if let pending = pendingPlace {
            recordMove(LastMove(
                player: pending.0,
                position: pending.1,
                quadrant: quadrant,
                clockwise: clockwise
            ))
            pendingPlace = nil
        }
        return true
    }

    func reset() {
        model = .empty()
        moveLog = []
        pendingPlace = nil
    }

    func replace(with newModel: BoardModel) {
        model = newModel
        moveLog = []
        pendingPlace = nil
    }

    private func recordMove(_ move: LastMove) {
        moveLog.insert(move, at: 0)
        if moveLog.count > 4 {
            moveLog = Array(moveLog.prefix(4))
        }
    }
}
