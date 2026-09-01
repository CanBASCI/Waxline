import Testing
@testable import Waxline

@MainActor
struct RotationTests {
    private let pattern: [[Cell]] = [
        [.red, .red, .indigo],
        [.indigo, .empty, .red],
        [.indigo, .indigo, .red]
    ]

    private let clockwise: [[Cell]] = [
        [.indigo, .indigo, .red],
        [.indigo, .empty, .red],
        [.red, .red, .indigo]
    ]

    private let counterClockwise: [[Cell]] = [
        [.indigo, .red, .red],
        [.red, .empty, .indigo],
        [.red, .indigo, .indigo]
    ]

    @Test func northwestClockwise() {
        var board = filled(quadrant: .nw, with: pattern)
        board.applyRotation(quadrant: .nw, clockwise: true)
        #expect(slice(board, .nw) == clockwise)
        #expect(otherQuadrantsEmpty(board, except: .nw))
    }

    @Test func northwestCounterClockwise() {
        var board = filled(quadrant: .nw, with: pattern)
        board.applyRotation(quadrant: .nw, clockwise: false)
        #expect(slice(board, .nw) == counterClockwise)
    }

    @Test func northeastClockwise() {
        var board = filled(quadrant: .ne, with: pattern)
        board.applyRotation(quadrant: .ne, clockwise: true)
        #expect(slice(board, .ne) == clockwise)
    }

    @Test func northeastCounterClockwise() {
        var board = filled(quadrant: .ne, with: pattern)
        board.applyRotation(quadrant: .ne, clockwise: false)
        #expect(slice(board, .ne) == counterClockwise)
    }

    @Test func southwestClockwise() {
        var board = filled(quadrant: .sw, with: pattern)
        board.applyRotation(quadrant: .sw, clockwise: true)
        #expect(slice(board, .sw) == clockwise)
    }

    @Test func southwestCounterClockwise() {
        var board = filled(quadrant: .sw, with: pattern)
        board.applyRotation(quadrant: .sw, clockwise: false)
        #expect(slice(board, .sw) == counterClockwise)
    }

    @Test func southeastClockwise() {
        var board = filled(quadrant: .se, with: pattern)
        board.applyRotation(quadrant: .se, clockwise: true)
        #expect(slice(board, .se) == clockwise)
    }

    @Test func southeastCounterClockwise() {
        var board = filled(quadrant: .se, with: pattern)
        board.applyRotation(quadrant: .se, clockwise: false)
        #expect(slice(board, .se) == counterClockwise)
    }

    @Test func centerCellStays() {
        var board = filled(quadrant: .nw, with: pattern)
        board.applyRotation(quadrant: .nw, clockwise: true)
        #expect(board.cells[1][1] == .empty)
        board.applyRotation(quadrant: .nw, clockwise: false)
        #expect(slice(board, .nw) == pattern)
    }

    private func filled(quadrant: Quadrant, with values: [[Cell]]) -> BoardModel {
        var board = BoardModel.empty()
        for r in 0..<3 {
            for c in 0..<3 {
                board.cells[quadrant.rowOffset + r][quadrant.colOffset + c] = values[r][c]
            }
        }
        return board
    }

    private func slice(_ board: BoardModel, _ quadrant: Quadrant) -> [[Cell]] {
        (0..<3).map { r in
            (0..<3).map { c in
                board.cells[quadrant.rowOffset + r][quadrant.colOffset + c]
            }
        }
    }

    private func otherQuadrantsEmpty(_ board: BoardModel, except keep: Quadrant) -> Bool {
        Quadrant.allCases.filter { $0 != keep }.allSatisfy { slice(board, $0).allSatisfy { $0.allSatisfy { $0 == .empty } } }
    }
}

@MainActor
struct WinCheckerTests {
    @Test func horizontalWinSpansTwoQuadrants() {
        var cells = emptyGrid()
        for col in 0..<5 { cells[1][col] = .red }
        let line = WinChecker.line(for: .red, cells: cells)
        #expect(line == (0..<5).map { Position(row: 1, col: $0) })
        #expect(WinChecker.status(of: cells) == .won(.red, line: line!))
    }

    @Test func verticalWinSpansTwoQuadrants() {
        var cells = emptyGrid()
        for row in 0..<5 { cells[row][1] = .indigo }
        let line = WinChecker.line(for: .indigo, cells: cells)
        #expect(line == (0..<5).map { Position(row: $0, col: 1) })
    }

    @Test func diagonalWinSpansTwoQuadrants() {
        var cells = emptyGrid()
        for i in 0..<5 { cells[i][i] = .red }
        let line = WinChecker.line(for: .red, cells: cells)
        #expect(line == (0..<5).map { Position(row: $0, col: $0) })
    }

    @Test func antiDiagonalWin() {
        var cells = emptyGrid()
        for i in 0..<5 { cells[i][5 - i] = .indigo }
        #expect(WinChecker.line(for: .indigo, cells: cells)?.count == 5)
    }

    @Test func doubleFiveIsDraw() {
        var cells = emptyGrid()
        for col in 0..<5 { cells[0][col] = .red }
        for col in 0..<5 { cells[5][col] = .indigo }
        #expect(WinChecker.status(of: cells) == .draw)
    }

    @Test func fullBoardWithoutFiveIsDraw() {
        let cells: [[Cell]] = [
            [.red, .red, .indigo, .red, .indigo, .indigo],
            [.indigo, .indigo, .red, .red, .indigo, .red],
            [.indigo, .indigo, .red, .indigo, .indigo, .red],
            [.red, .indigo, .red, .red, .red, .red],
            [.indigo, .red, .indigo, .red, .red, .indigo],
            [.indigo, .red, .indigo, .red, .red, .indigo]
        ]
        #expect(WinChecker.line(for: .red, cells: cells) == nil)
        #expect(WinChecker.line(for: .indigo, cells: cells) == nil)
        #expect(WinChecker.status(of: cells) == .draw)
    }

    @Test func rotationCreatesDoubleFiveDraw() {
        var board = BoardModel.empty()
        board.cells[0][0] = .red
        board.cells[0][1] = .red
        board.cells[0][2] = .red
        board.cells[2][0] = .indigo
        board.cells[2][1] = .indigo
        board.cells[2][2] = .indigo
        board.cells[3][0] = .indigo
        board.cells[4][0] = .indigo
        board.cells[3][2] = .red
        board.cells[4][2] = .red
        #expect(WinChecker.status(of: board.cells) == .playing)
        board.phase = .rotate
        let rotated = board.rotate(quadrant: .nw, clockwise: true)
        #expect(rotated)
        #expect(board.status == .draw)
    }

    private func emptyGrid() -> [[Cell]] {
        Array(repeating: Array(repeating: Cell.empty, count: 6), count: 6)
    }
}

@MainActor
struct BoardModelTests {
    @Test func redStartsInPlacePhase() {
        let board = BoardModel.empty()
        #expect(board.currentPlayer == .red)
        #expect(board.phase == .place)
    }

    @Test func winAfterPlacementSkipsRotation() {
        var board = BoardModel.empty()
        for col in 0..<4 { board.cells[2][col] = .red }
        let placed = board.place(at: Position(row: 2, col: 4))
        #expect(placed)
        if case .won(.red, let line) = board.status {
            #expect(line.count == 5)
        } else {
            Issue.record("Expected red win after placement")
        }
        #expect(board.phase == .place || board.status != .playing)
    }

    @Test func mustRotateBeforeNextPlace() {
        var board = BoardModel.empty()
        let first = board.place(at: Position(row: 0, col: 0))
        #expect(first)
        #expect(board.phase == .rotate)
        let second = board.place(at: Position(row: 0, col: 1))
        #expect(second == false)
        let rotated = board.rotate(quadrant: .se, clockwise: false)
        #expect(rotated)
        #expect(board.currentPlayer == .indigo)
        #expect(board.phase == .place)
    }
}
