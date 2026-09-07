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

    var localHumanPlayer: Player? {
        switch mode {
        case .local, .gameCenter: nil
        case .ai: .red
        }
    }

    func place(at position: Position) -> Bool {
        model.place(at: position)
    }

    func rotate(quadrant: Quadrant, clockwise: Bool) -> Bool {
        model.rotate(quadrant: quadrant, clockwise: clockwise)
    }

    func reset() {
        model = .empty()
    }

    func replace(with newModel: BoardModel) {
        model = newModel
    }
}
