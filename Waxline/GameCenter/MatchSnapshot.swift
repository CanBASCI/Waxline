import Foundation

struct MatchSnapshot: Codable, Equatable, Sendable {
    var version: Int
    var cells: [UInt8]
    var currentPlayer: Int
    var phase: Int
    var winner: Int
    var winRows: [Int]
    var winCols: [Int]

    static func from(_ model: BoardModel) -> MatchSnapshot {
        var cells: [UInt8] = []
        cells.reserveCapacity(36)
        for row in 0..<6 {
            for col in 0..<6 {
                cells.append(UInt8(model.cells[row][col].rawValue))
            }
        }
        var winner = 0
        var winRows: [Int] = []
        var winCols: [Int] = []
        switch model.status {
        case .playing:
            winner = 0
        case .draw:
            winner = 3
        case .won(let player, let line):
            winner = player.rawValue
            winRows = line.map(\.row)
            winCols = line.map(\.col)
        }
        return MatchSnapshot(
            version: 1,
            cells: cells,
            currentPlayer: model.currentPlayer.rawValue,
            phase: model.phase.rawValue,
            winner: winner,
            winRows: winRows,
            winCols: winCols
        )
    }

    func toModel() -> BoardModel {
        var grid = Array(repeating: Array(repeating: Cell.empty, count: 6), count: 6)
        for index in 0..<min(36, cells.count) {
            let row = index / 6
            let col = index % 6
            grid[row][col] = Cell(rawValue: Int(cells[index])) ?? .empty
        }
        let player = Player(rawValue: currentPlayer) ?? .red
        let turn = TurnPhase(rawValue: phase) ?? .place
        let status: GameStatus
        switch winner {
        case 1:
            let line = zip(winRows, winCols).map { Position(row: $0, col: $1) }
            status = .won(.red, line: line)
        case 2:
            let line = zip(winRows, winCols).map { Position(row: $0, col: $1) }
            status = .won(.indigo, line: line)
        case 3:
            status = .draw
        default:
            status = WinChecker.status(of: grid)
        }
        let checked = status == .playing ? WinChecker.status(of: grid) : status
        return BoardModel(
            cells: grid,
            currentPlayer: player,
            phase: turn,
            status: checked,
            lastPlacement: nil
        )
    }

    func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    static func decode(_ data: Data) -> MatchSnapshot? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(MatchSnapshot.self, from: data)
    }
}
