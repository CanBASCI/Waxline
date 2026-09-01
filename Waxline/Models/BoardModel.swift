import Foundation

struct BoardModel: Sendable, Equatable {
    var cells: [[Cell]]
    var currentPlayer: Player
    var phase: TurnPhase
    var status: GameStatus
    var lastPlacement: Position?

    static func empty() -> BoardModel {
        BoardModel(
            cells: Array(repeating: Array(repeating: .empty, count: 6), count: 6),
            currentPlayer: .red,
            phase: .place,
            status: .playing,
            lastPlacement: nil
        )
    }

    func cell(at position: Position) -> Cell {
        guard position.isOnBoard else { return .empty }
        return cells[position.row][position.col]
    }

    func emptyPositions() -> [Position] {
        var result: [Position] = []
        for row in 0..<6 {
            for col in 0..<6 where cells[row][col] == .empty {
                result.append(Position(row: row, col: col))
            }
        }
        return result
    }

    mutating func place(at position: Position) -> Bool {
        guard status == .playing, phase == .place, position.isOnBoard else { return false }
        guard cells[position.row][position.col] == .empty else { return false }
        cells[position.row][position.col] = currentPlayer.cell
        lastPlacement = position
        status = WinChecker.status(of: cells)
        if status == .playing {
            phase = .rotate
        }
        return true
    }

    mutating func rotate(quadrant: Quadrant, clockwise: Bool) -> Bool {
        guard status == .playing, phase == .rotate else { return false }
        applyRotation(quadrant: quadrant, clockwise: clockwise)
        status = WinChecker.status(of: cells)
        if status == .playing {
            phase = .place
            currentPlayer = currentPlayer.opponent
        }
        return true
    }

    mutating func applyRotation(quadrant: Quadrant, clockwise: Bool) {
        let r0 = quadrant.rowOffset
        let c0 = quadrant.colOffset
        var slice = Array(repeating: Array(repeating: Cell.empty, count: 3), count: 3)
        for r in 0..<3 {
            for c in 0..<3 {
                slice[r][c] = cells[r0 + r][c0 + c]
            }
        }
        var rotated = slice
        for r in 0..<3 {
            for c in 0..<3 {
                if clockwise {
                    rotated[c][2 - r] = slice[r][c]
                } else {
                    rotated[2 - c][r] = slice[r][c]
                }
            }
        }
        for r in 0..<3 {
            for c in 0..<3 {
                cells[r0 + r][c0 + c] = rotated[r][c]
            }
        }
    }
}
