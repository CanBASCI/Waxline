import Foundation
import Observation

@Observable
final class GameState {
    private(set) var model: BoardModel
    private(set) var series = MatchSeries()
    let mode: GameMode

    init(mode: GameMode, model: BoardModel = .empty(), series: MatchSeries = MatchSeries()) {
        self.mode = mode
        self.model = model
        self.series = series
    }

    var cells: [[Cell]] { model.cells }
    var currentPlayer: Player { model.currentPlayer }
    var phase: TurnPhase { model.phase }
    var status: GameStatus { model.status }
    var lastPlacement: Position? { model.lastPlacement }
    var isFinished: Bool { model.status != .playing }

    var localHumanPlayer: Player? {
        switch mode {
        case .gameCenter: nil
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

    func recordSeriesResult(you player: Player) {
        switch model.status {
        case .won(let winner, _):
            if winner == player {
                series.you += 1
            } else {
                series.opponent += 1
            }
        case .draw:
            series.draws += 1
        case .playing:
            break
        }
    }

    func replace(with newModel: BoardModel) {
        model = newModel
    }
}
