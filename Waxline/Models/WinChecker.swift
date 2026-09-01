import Foundation

enum WinChecker {
    private static let directions: [(Int, Int)] = [(0, 1), (1, 0), (1, 1), (1, -1)]

    static func line(for player: Player, cells: [[Cell]]) -> [Position]? {
        for row in 0..<6 {
            for col in 0..<6 {
                for dir in directions {
                    let prevRow = row - dir.0
                    let prevCol = col - dir.1
                    if prevRow >= 0, prevRow < 6, prevCol >= 0, prevCol < 6,
                       cells[prevRow][prevCol] == player.cell {
                        continue
                    }
                    var line: [Position] = []
                    var r = row
                    var c = col
                    while r >= 0, r < 6, c >= 0, c < 6, cells[r][c] == player.cell {
                        line.append(Position(row: r, col: c))
                        r += dir.0
                        c += dir.1
                    }
                    if line.count >= 5 {
                        return Array(line.prefix(5))
                    }
                }
            }
        }
        return nil
    }

    static func status(of cells: [[Cell]]) -> GameStatus {
        let red = line(for: .red, cells: cells)
        let indigo = line(for: .indigo, cells: cells)
        if red != nil, indigo != nil { return .draw }
        if let red { return .won(.red, line: red) }
        if let indigo { return .won(.indigo, line: indigo) }
        if cells.allSatisfy({ row in row.allSatisfy { $0 != .empty } }) {
            return .draw
        }
        return .playing
    }
}
