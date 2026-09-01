import Foundation

enum GameAI {
    static func choosePlacement(model: BoardModel, level: AILevel) -> Position {
        let empties = model.emptyPositions()
        precondition(!empties.isEmpty)
        switch level {
        case .easy:
            return randomPlacement(model: model, empties: empties)
        case .medium, .hard:
            return bestTurn(model: model, level: level).place
        }
    }

    static func chooseRotation(model: BoardModel, level: AILevel) -> (Quadrant, Bool) {
        switch level {
        case .easy:
            if let block = blockingRotation(model: model) { return block }
            let clockwise = Bool.random()
            return (Quadrant.allCases.randomElement() ?? .nw, clockwise)
        case .medium, .hard:
            return bestRotation(model: model, level: level)
        }
    }

    private struct FullTurn {
        var place: Position
        var quadrant: Quadrant
        var clockwise: Bool
        var score: Int
    }

    private static func randomPlacement(model: BoardModel, empties: [Position]) -> Position {
        if let win = winningPlacement(model: model, player: model.currentPlayer) { return win }
        if let block = winningPlacement(model: model, player: model.currentPlayer.opponent) { return block }
        return empties.randomElement() ?? Position(row: 0, col: 0)
    }

    private static func winningPlacement(model: BoardModel, player: Player) -> Position? {
        for position in model.emptyPositions() {
            var copy = model
            copy.cells[position.row][position.col] = player.cell
            if WinChecker.line(for: player, cells: copy.cells) != nil {
                return position
            }
        }
        return nil
    }

    private static func blockingRotation(model: BoardModel) -> (Quadrant, Bool)? {
        let opponent = model.currentPlayer.opponent
        for quadrant in Quadrant.allCases {
            for clockwise in [true, false] {
                var copy = model
                copy.applyRotation(quadrant: quadrant, clockwise: clockwise)
                if WinChecker.line(for: opponent, cells: copy.cells) == nil {
                    if WinChecker.line(for: model.currentPlayer, cells: copy.cells) != nil {
                        return (quadrant, clockwise)
                    }
                }
            }
        }
        for quadrant in Quadrant.allCases {
            for clockwise in [true, false] {
                var copy = model
                copy.applyRotation(quadrant: quadrant, clockwise: clockwise)
                if WinChecker.line(for: opponent, cells: copy.cells) == nil {
                    return (quadrant, clockwise)
                }
            }
        }
        return nil
    }

    private static func bestTurn(model: BoardModel, level: AILevel) -> FullTurn {
        let depth = level == .hard ? 2 : 1
        let placements = candidatePlacements(model: model)
        var best: FullTurn?
        var alpha = Int.min / 4
        let beta = Int.max / 4
        let me = model.currentPlayer

        for place in placements {
            var afterPlace = model
            guard afterPlace.place(at: place) else { continue }
            if afterPlace.status != .playing {
                let score = evaluate(afterPlace, for: me)
                let turn = FullTurn(place: place, quadrant: .nw, clockwise: true, score: score)
                if best == nil || turn.score > best!.score { best = turn }
                continue
            }
            for quadrant in Quadrant.allCases {
                for clockwise in [true, false] {
                    var after = afterPlace
                    guard after.rotate(quadrant: quadrant, clockwise: clockwise) else { continue }
                    let score: Int
                    if after.status != .playing || depth <= 1 {
                        score = evaluate(after, for: me)
                    } else {
                        score = minimax(after, depth: depth - 1, maximizing: false, me: me, alpha: alpha, beta: beta)
                    }
                    if best == nil || score > best!.score {
                        best = FullTurn(place: place, quadrant: quadrant, clockwise: clockwise, score: score)
                        alpha = max(alpha, score)
                    }
                }
            }
        }
        return best ?? FullTurn(place: placements[0], quadrant: .nw, clockwise: true, score: 0)
    }

    private static func bestRotation(model: BoardModel, level: AILevel) -> (Quadrant, Bool) {
        let me = model.currentPlayer
        let depth = level == .hard ? 2 : 1
        var best: (Quadrant, Bool, Int)?
        for quadrant in Quadrant.allCases {
            for clockwise in [true, false] {
                var after = model
                guard after.rotate(quadrant: quadrant, clockwise: clockwise) else { continue }
                let score: Int
                if after.status != .playing || depth <= 1 {
                    score = evaluate(after, for: me)
                } else {
                    score = minimax(after, depth: depth - 1, maximizing: false, me: me, alpha: Int.min / 4, beta: Int.max / 4)
                }
                if best == nil || score > best!.2 {
                    best = (quadrant, clockwise, score)
                }
            }
        }
        return (best?.0 ?? .nw, best?.1 ?? true)
    }

    private static func minimax(
        _ model: BoardModel,
        depth: Int,
        maximizing: Bool,
        me: Player,
        alpha: Int,
        beta: Int
    ) -> Int {
        if depth == 0 || model.status != .playing {
            return evaluate(model, for: me)
        }
        var alpha = alpha
        var beta = beta
        let placements = candidatePlacements(model: model)
        if maximizing {
            var best = Int.min / 4
            for place in placements {
                var afterPlace = model
                guard afterPlace.place(at: place) else { continue }
                if afterPlace.status != .playing {
                    best = max(best, evaluate(afterPlace, for: me))
                    alpha = max(alpha, best)
                    if beta <= alpha { break }
                    continue
                }
                for quadrant in Quadrant.allCases {
                    for clockwise in [true, false] {
                        var after = afterPlace
                        guard after.rotate(quadrant: quadrant, clockwise: clockwise) else { continue }
                        let score = minimax(after, depth: depth - 1, maximizing: false, me: me, alpha: alpha, beta: beta)
                        best = max(best, score)
                        alpha = max(alpha, best)
                        if beta <= alpha { return best }
                    }
                }
            }
            return best
        } else {
            var best = Int.max / 4
            for place in placements {
                var afterPlace = model
                guard afterPlace.place(at: place) else { continue }
                if afterPlace.status != .playing {
                    best = min(best, evaluate(afterPlace, for: me))
                    beta = min(beta, best)
                    if beta <= alpha { break }
                    continue
                }
                for quadrant in Quadrant.allCases {
                    for clockwise in [true, false] {
                        var after = afterPlace
                        guard after.rotate(quadrant: quadrant, clockwise: clockwise) else { continue }
                        let score = minimax(after, depth: depth - 1, maximizing: true, me: me, alpha: alpha, beta: beta)
                        best = min(best, score)
                        beta = min(beta, best)
                        if beta <= alpha { return best }
                    }
                }
            }
            return best
        }
    }

    private static func candidatePlacements(model: BoardModel) -> [Position] {
        let empties = model.emptyPositions()
        if empties.count <= 10 { return empties }
        var occupied = false
        for row in 0..<6 {
            for col in 0..<6 where model.cells[row][col] != .empty { occupied = true }
        }
        if !occupied {
            return [Position(row: 2, col: 2), Position(row: 2, col: 3), Position(row: 3, col: 2), Position(row: 3, col: 3)]
        }
        var near: [Position] = []
        for pos in empties where isNearOccupied(pos, cells: model.cells) {
            near.append(pos)
        }
        if near.isEmpty { return Array(empties.prefix(12)) }
        if near.count > 14 {
            near.sort { centerWeight($0) > centerWeight($1) }
            return Array(near.prefix(14))
        }
        return near
    }

    private static func isNearOccupied(_ position: Position, cells: [[Cell]]) -> Bool {
        for dr in -1...1 {
            for dc in -1...1 {
                let r = position.row + dr
                let c = position.col + dc
                if r >= 0, r < 6, c >= 0, c < 6, cells[r][c] != .empty { return true }
            }
        }
        return false
    }

    private static func centerWeight(_ position: Position) -> Int {
        let wr = 2.5 - abs(Double(position.row) - 2.5)
        let wc = 2.5 - abs(Double(position.col) - 2.5)
        return Int((wr + wc) * 10)
    }

    private static func evaluate(_ model: BoardModel, for me: Player) -> Int {
        switch model.status {
        case .won(let player, _):
            return player == me ? 100_000 : -100_000
        case .draw:
            return 0
        case .playing:
            break
        }
        let mine = threatScore(cells: model.cells, player: me)
        let theirs = threatScore(cells: model.cells, player: me.opponent)
        var center = 0
        for row in 0..<6 {
            for col in 0..<6 {
                if model.cells[row][col] == me.cell {
                    center += centerWeight(Position(row: row, col: col))
                } else if model.cells[row][col] == me.opponent.cell {
                    center -= centerWeight(Position(row: row, col: col))
                }
            }
        }
        return mine - theirs + center
    }

    private static func threatScore(cells: [[Cell]], player: Player) -> Int {
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        var score = 0
        for row in 0..<6 {
            for col in 0..<6 {
                for dir in dirs {
                    let prevR = row - dir.0
                    let prevC = col - dir.1
                    if prevR >= 0, prevR < 6, prevC >= 0, prevC < 6, cells[prevR][prevC] == player.cell {
                        continue
                    }
                    var run = 0
                    var openEnds = 0
                    if prevR < 0 || prevR >= 6 || prevC < 0 || prevC >= 6 || cells[prevR][prevC] == .empty {
                        openEnds += 1
                    }
                    var r = row
                    var c = col
                    while r >= 0, r < 6, c >= 0, c < 6, cells[r][c] == player.cell {
                        run += 1
                        r += dir.0
                        c += dir.1
                    }
                    if r >= 0, r < 6, c >= 0, c < 6, cells[r][c] == .empty {
                        openEnds += 1
                    }
                    guard run > 0 else { continue }
                    switch run {
                    case 4: score += 800 * openEnds
                    case 3: score += 80 * max(openEnds, 1)
                    case 2: score += 12 * openEnds
                    default: score += run
                    }
                }
            }
        }
        return score
    }
}
