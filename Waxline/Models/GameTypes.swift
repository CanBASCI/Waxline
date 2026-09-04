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
    case local
    case ai(AILevel)
    case gameCenter
}

enum GameSkin: Equatable {
    case classic
    case sakura
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
    case turkish

    var id: String { rawValue }

    var locale: Locale? {
        switch self {
        case .system: nil
        case .english: Locale(identifier: "en")
        case .turkish: Locale(identifier: "tr")
        }
    }
}

enum SealPalette: String, Sendable, Codable, CaseIterable {
    case classic
    case mono
}

enum TableFinish: String, Sendable, Codable, CaseIterable {
    case walnut
    case ebony
    case oak
}

enum TabletFinish: String, Sendable, Codable, CaseIterable {
    case granite
    case slate
    case sand
}

enum SakuraTableTheme: String, Sendable, CaseIterable {
    case oak
    case honey
    case plank
    case cedar

    var colorResource: String {
        switch self {
        case .oak: "sakura_table_color"
        case .honey: "sakura_table_honey_color"
        case .plank: "sakura_table_plank_color"
        case .cedar: "sakura_table_cedar_color"
        }
    }

    var roughResource: String {
        switch self {
        case .oak: "sakura_table_rough"
        case .honey: "sakura_table_honey_rough"
        case .plank: "sakura_table_plank_rough"
        case .cedar: "sakura_table_cedar_rough"
        }
    }
}

enum SakuraTabletTheme: String, Sendable, CaseIterable {
    case grey
    case white
    case taupe
    case charcoal
    case paper
    case glass

    var colorResource: String? {
        switch self {
        case .grey: "sakura_tablet_color"
        case .white: "sakura_tablet_white_color"
        case .taupe: "sakura_tablet_taupe_color"
        case .charcoal: "sakura_tablet_charcoal_color"
        case .paper: "sakura_tablet_paper_color"
        case .glass: nil
        }
    }

    var roughResource: String? {
        switch self {
        case .grey: "sakura_tablet_rough"
        case .white: "sakura_tablet_white_rough"
        case .taupe: "sakura_tablet_taupe_rough"
        case .charcoal: "sakura_tablet_charcoal_rough"
        case .paper: "sakura_tablet_paper_rough"
        case .glass: nil
        }
    }
}

struct LastMove: Sendable, Equatable, Identifiable {
    let id: UUID
    var player: Player
    var position: Position
    var quadrant: Quadrant?
    var clockwise: Bool?

    init(player: Player, position: Position, quadrant: Quadrant?, clockwise: Bool?) {
        self.id = UUID()
        self.player = player
        self.position = position
        self.quadrant = quadrant
        self.clockwise = clockwise
    }
}

extension CaseIterable where Self: Equatable {
    mutating func cycle() {
        let all = Array(Self.allCases)
        guard let index = all.firstIndex(of: self) else { return }
        self = all[(index + 1) % all.count]
    }
}
