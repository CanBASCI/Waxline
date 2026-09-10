import Foundation

enum Cell: Int, Sendable, Codable, Equatable, Hashable {
    case empty = 0
    case red = 1
    case indigo = 2
}

enum Player: Int, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case red = 1
    case indigo = 2

    var cell: Cell {
        self == .red ? .red : .indigo
    }

    var opponent: Player {
        self == .red ? .indigo : .red
    }
}

enum Quadrant: Int, Sendable, Codable, Equatable, CaseIterable {
    case nw = 0
    case ne = 1
    case sw = 2
    case se = 3

    var rowOffset: Int { self == .nw || self == .ne ? 0 : 3 }
    var colOffset: Int { self == .nw || self == .sw ? 0 : 3 }
}

enum TurnPhase: Int, Sendable, Codable, Equatable {
    case place = 0
    case rotate = 1
}

struct LastRotation: Sendable, Codable, Equatable {
    var quadrant: Quadrant
    var clockwise: Bool
}

struct Position: Sendable, Codable, Equatable, Hashable {
    var row: Int
    var col: Int

    var isOnBoard: Bool {
        row >= 0 && row < 6 && col >= 0 && col < 6
    }
}

enum GameStatus: Sendable, Equatable {
    case playing
    case won(Player, line: [Position])
    case draw
}

enum GameMode: Equatable, Hashable {
    case ai(AILevel)
    case gameCenter
}

struct MatchSeries: Equatable, Sendable {
    var you = 0
    var opponent = 0
    var draws = 0

    var hasHands: Bool { you + opponent + draws > 0 }

    static func points(forWinningLine length: Int) -> Int {
        length >= 6 ? 2 : 1
    }
}

enum MatchSeating {
    static func starter(forHand index: Int) -> Player {
        index % 2 == 0 ? .red : .indigo
    }

    static func color(localID: String, inviterID: String) -> Player {
        localID == inviterID ? .red : .indigo
    }
}

enum SakuraLook: String, Sendable, CaseIterable {
    case color
    case mono
    case neon
}

enum AILevel: String, Sendable, Codable, CaseIterable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }
}

enum LanguageOverride: String, Sendable, Codable, CaseIterable, Identifiable {
    case system
    case english
    case german
    case spanish
    case japanese
    case turkish

    var id: String { rawValue }

    nonisolated var locale: Locale? {
        switch self {
        case .system: nil
        case .english: Locale(identifier: "en")
        case .german: Locale(identifier: "de")
        case .spanish: Locale(identifier: "es")
        case .japanese: Locale(identifier: "ja")
        case .turkish: Locale(identifier: "tr")
        }
    }

    nonisolated var catalogCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .german: "de"
        case .spanish: "es"
        case .japanese: "ja"
        case .turkish: "tr"
        }
    }
}

enum SealPalette: String, Sendable, Codable, CaseIterable {
    case classic
    case mono
    case neon
}

enum SakuraTabletTheme: String, Sendable {
    case charcoal
    case blossom
    case neon

    var colorResource: String {
        switch self {
        case .charcoal: "sakura_tablet_charcoal_color"
        case .blossom: "sakura_tablet_blossom_color"
        case .neon: "sakura_tablet_neon_color"
        }
    }
}

extension CaseIterable where Self: Equatable {
    mutating func cycle() {
        let all = Array(Self.allCases)
        guard let index = all.firstIndex(of: self) else { return }
        self = all[(index + 1) % all.count]
    }
}
