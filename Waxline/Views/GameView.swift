import SwiftUI

struct GameView: View {
    @Bindable var game: GameState
    var skin: GameSkin = .classic
    var onExit: () -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter
    @State private var scene = BoardSceneController()
    @State private var selectedQuadrant: Quadrant?
    @State private var busy = false
    @State private var showResult = false
    @State private var is3DView = false
    @State private var showLookPanel = false
    @State private var sakuraLook: SakuraLook = .mono
    @State private var sakuraTablet: SakuraTabletTheme = .charcoal
    @State private var resultTask: Task<Void, Never>?
    @State private var timerTask: Task<Void, Never>?
    @State private var turnSecondsLeft = 15
    @State private var boardRect: CGRect = .zero
    @State private var tableSpinActive = false
    @State private var canvasSize = CGSize(width: 390, height: 844)
    private var isCompactCanvas: Bool { canvasSize.height < 720 }
    private var boardGutter: CGFloat {
        skin == .sakura && isCompactCanvas ? 16 : 30
    }
    private var moveLogSlotHeight: CGFloat {
        skin == .sakura && isCompactCanvas ? 88 : 108
    }
    private var overlayTypeSize: CGFloat {
        skin == .sakura && isCompactCanvas ? 14 : 16
    }
    private var sakuraBoardSide: CGFloat {
        let chrome: CGFloat = 12 + 32
            + boardGutter + 68 + 8
            + 44
            + 36
            + 18 + moveLogSlotHeight + 8
            + boardGutter
        return min(canvasSize.width, max(200, canvasSize.height - chrome))
    }
    private let boardBottomTrim: CGFloat = 40
    private let sealBaseSize: CGFloat = 16
    private let sealBaseStep: CGFloat = 3
    private let sealBaseRowGap: CGFloat = 8
    private let sealBasePileGap: CGFloat = 5
    private let turnTimeLimit = 15

    private var sealScale: CGFloat {
        guard skin == .sakura else { return 1 }
        let fullHeight = (sealBaseSize + sealBaseStep * 5) * 2 + sealBaseRowGap
        return moveLogSlotHeight / fullHeight
    }

    private let logLineSpacing: CGFloat = 4
    private var logLineHeight: CGFloat {
        (moveLogSlotHeight - logLineSpacing * 3) / 4
    }

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    var body: some View {
        GeometryReader { geo in
            playStack
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, size in canvasSize = size }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .coordinateSpace(name: "gameCanvas")
        .onPreferenceChange(BoardRectKey.self) { boardRect = $0 }
        .contentShape(Rectangle())
        .simultaneousGesture(tableSpinGesture)
        .background {
            if skin == .sakura {
                ZStack(alignment: .bottom) {
                    GameLoopBackdrop(resource: "gamescreensakuravideo_2", ext: "mov")
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0),
                            Color.black.opacity(0.36),
                            Color.black.opacity(0.58)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 150)
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            } else {
                canvas.ignoresSafeArea()
            }
        }
        .preferredColorScheme(skin == .sakura ? .dark : (isDark ? .dark : .light))
        .onAppear { configureScene() }
        .onChange(of: game.status) { _, newStatus in
            if newStatus != .playing {
                stopTurnTimer()
                scene.abandonTabletDrag()
                highlightWin()
                HapticsService.win(enabled: settings.hapticsEnabled)
                SoundService.win(enabled: settings.soundEnabled)
                resultTask?.cancel()
                resultTask = Task {
                    try? await Task.sleep(for: .milliseconds(1100))
                    guard !Task.isCancelled else { return }
                    showResult = true
                }
            }
        }
        .onChange(of: gameCenter.matchRevision) { _, _ in
            reloadRemoteMatch()
        }
        .sheet(isPresented: $showResult) {
            ResultSheet(game: game, skin: usesSakuraSurfaces ? .sakura : .classic, seals: activeSeals, onAgain: replay, onMenu: onExit)
                .environment(\.colorScheme, resultScheme)
                .preferredColorScheme(resultScheme)
        }
        .onDisappear {
            resultTask?.cancel()
            stopTurnTimer()
            finishTableSpin()
        }
    }

    private var playStack: some View {
        VStack(spacing: 0) {
            header
            turnBanner
            if skin == .sakura {
                Spacer(minLength: 0)
                if showsTurnTimer || showsPerspectiveChip {
                    HStack(alignment: .center, spacing: 8) {
                        if showsTurnTimer {
                            turnTimer
                        }
                        Spacer(minLength: 8)
                        if showsPerspectiveChip {
                            perspectiveChip
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            BoardSceneView(controller: scene)
                .aspectRatio(skin == .sakura ? 1 : 0.72, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(width: skin == .sakura ? sakuraBoardSide : nil, height: skin == .sakura ? sakuraBoardSide : nil)
                .fixedSize(horizontal: false, vertical: skin != .sakura)
                .padding(.bottom, skin == .sakura ? 0 : -boardBottomTrim)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    CornerBrackets(cornerRadius: 12, length: 18)
                        .stroke(boardInk.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .padding(1)
                        .allowsHitTesting(false)
                }
                .overlay {
                    if showLookPanel {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    showLookPanel = false
                                }
                            }
                    }
                }
                .overlay(alignment: .bottom) {
                    if skin != .sakura, boardStatusText != nil {
                        boardStatus
                    }
                }
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: BoardRectKey.self, value: geo.frame(in: .named("gameCanvas")))
                    }
                }
                .padding(.top, 0)
                .padding(.bottom, boardGutter)
            if skin == .sakura {
                VStack(spacing: 0) {
                    boardStatus
                    footer
                }
            } else {
                footer
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onExit) {
                Text(t("menu"))
                    .font(bannerFont)
                    .foregroundStyle(hudChromeInk)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(hudChromeFill, in: Capsule())
                    .overlay {
                        Capsule().stroke(hudChromeInk.opacity(0.35), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            lookMenu
                .shadow(color: textHalo, radius: skin == .sakura ? 8 : 0)
        }
        .zIndex(1)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 0)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if showLookPanel { showLookPanel = false }
                }
        }
    }

    private var turnBanner: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                SealMark(color: currentColor, motif: sealMotif, outline: sealOutline)
                    .frame(width: 22, height: 22)
                Text(turnTitle)
                    .font(bannerFont)
                    .foregroundStyle(skin == .sakura ? Theme.ink(dark: true) : titleColor)
                    .modifier(OverlayReadable(enabled: skin == .sakura))
                Spacer(minLength: 8)
                if showsTurnTimer, skin != .sakura {
                    turnTimer
                }
            }
            HStack(alignment: .center, spacing: 8) {
                if game.status == .playing {
                    turnSteps
                }
                Spacer(minLength: 8)
                if showsPerspectiveChip, skin != .sakura {
                    perspectiveChip
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, boardGutter)
        .padding(.bottom, skin == .sakura ? 8 : boardGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: textHalo, radius: skin == .sakura ? 8 : 0)
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            moveLogList
            sealReserve
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, skin == .sakura ? 2 : 12)
        .shadow(color: overlayHalo, radius: skin == .sakura ? 8 : 0)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(t("last_move"))
        .accessibilityValue(game.moveLog.map(moveLine).joined(separator: ", "))
    }

    private var moveLogList: some View {
        VStack(alignment: .leading, spacing: skin == .sakura ? logLineSpacing : 4) {
            ForEach(Array(game.moveLog.enumerated()), id: \.element.id) { index, move in
                moveLogLine(index: index, move: move)
            }
        }
        .frame(maxWidth: .infinity, minHeight: logSlotMinHeight, maxHeight: logSlotMaxHeight, alignment: .bottom)
    }

    private var logSlotMinHeight: CGFloat {
        skin == .sakura ? moveLogSlotHeight : 0
    }

    private var logSlotMaxHeight: CGFloat? {
        skin == .sakura ? moveLogSlotHeight : nil
    }

    private func moveLogLine(index: Int, move: LastMove) -> some View {
        Text(moveLine(move))
            .font(logFont(index: index))
            .foregroundStyle(overlayInk.opacity(moveLogOpacity(index)))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .modifier(OverlayReadable(enabled: skin == .sakura))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: skin == .sakura ? logLineHeight : nil)
    }

    private var sealReserve: some View {
        VStack(alignment: .trailing, spacing: sealBaseRowGap * sealScale) {
            sealPiles(for: .red)
            sealPiles(for: .indigo)
        }
        .frame(height: skin == .sakura ? moveLogSlotHeight : nil, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("seal_reserve"))
        .accessibilityValue(
            "\(remainingSeals(for: .red)), \(remainingSeals(for: .indigo))"
        )
    }

    private func sealPiles(for player: Player) -> some View {
        HStack(spacing: sealBasePileGap * sealScale) {
            ForEach(0..<3, id: \.self) { pile in
                sealPile(count: pileCount(for: player, pile: pile), player: player)
            }
        }
    }

    private func sealPile(count: Int, player: Player) -> some View {
        let size = sealBaseSize * sealScale
        let step = sealBaseStep * sealScale
        return ZStack(alignment: .bottom) {
            ForEach(0..<count, id: \.self) { index in
                SealMark(
                    color: Theme.seal(player, palette: activeSeals, skin: usesSakuraSurfaces ? .sakura : .classic),
                    motif: reserveMotif(player),
                    outline: stackEdge(for: player),
                    outlineWidth: 1.2 * sealScale
                )
                .frame(width: size, height: size)
                .offset(y: -CGFloat(index) * step)
            }
        }
        .frame(width: size, height: size + step * 5, alignment: .bottom)
    }

    private func remainingSeals(for player: Player) -> Int {
        let placed = game.cells.reduce(0) { sum, row in
            sum + row.filter { $0 == player.cell }.count
        }
        return max(0, 18 - placed)
    }

    private func pileCount(for player: Player, pile: Int) -> Int {
        let remaining = remainingSeals(for: player)
        return min(6, max(0, remaining - (2 - pile) * 6))
    }

    private func reserveMotif(_ player: Player) -> Color {
        if activeSeals == .mono, player == .indigo {
            return Theme.waxBlack
        }
        return Theme.gold
    }

    private func stackEdge(for player: Player) -> Color {
        let isWhite = activeSeals == .mono && player == .indigo
        return isWhite ? Theme.waxBlack : (skin == .sakura ? Color.white : Theme.cream)
    }

    private var boardStatus: some View {
        Text(boardStatusText ?? " ")
            .font(skin == .sakura ? .system(size: overlayTypeSize, weight: .regular, design: .serif) : .system(.subheadline, design: .serif))
            .foregroundStyle(skin == .sakura ? Theme.ink(dark: true) : overlayInk.opacity(0.7))
            .modifier(OverlayReadable(enabled: skin == .sakura))
            .shadow(color: skin == .sakura ? .clear : overlayHalo, radius: skin == .sakura ? 0 : 6)
            .opacity(boardStatusText == nil ? 0 : 1)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
    }

    private var boardStatusText: String? {
        if canAct, !busy {
            if game.phase == .place {
                return t("place_hint")
            }
            if game.phase == .rotate {
                return t("rotate_hint")
            }
        }
        if busy, isAIThinking {
            return t(activeSeals == .mono ? "waiting_white" : "waiting_ai")
        }
        if game.mode == .gameCenter, !isLocalTurn {
            return t("turn_waiting")
        }
        return nil
    }

    private var tableSpinGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("gameCanvas"))
            .onChanged { value in
                guard boardRect.width > 8, !boardRect.contains(value.startLocation) else { return }
                guard let view = scene.scnView else { return }
                let point = CGPoint(
                    x: value.location.x - boardRect.minX,
                    y: value.location.y - boardRect.minY
                )
                if tableSpinActive {
                    scene.updateTablePan(at: point, in: view)
                } else {
                    tableSpinActive = true
                    scene.beginTablePan(at: point, in: view)
                }
            }
            .onEnded { _ in
                finishTableSpin()
            }
    }

    private func finishTableSpin() {
        guard tableSpinActive else { return }
        tableSpinActive = false
        scene.endTablePan()
    }

    private var perspectiveChip: some View {
        Button {
            finishTableSpin()
            is3DView.toggle()
            scene.setPerspective3D(is3DView)
            HapticsService.select(enabled: settings.hapticsEnabled)
        } label: {
            Text(is3DView ? t("view_3d") : t("view_2d"))
                .font(skin == .sakura ? hudMeterFont : .system(.subheadline, design: .serif).weight(.medium))
                .foregroundStyle(ink)
                .padding(.horizontal, usesWhiteSealChrome ? 8 : 10)
                .padding(.vertical, usesWhiteSealChrome ? 2 : 5)
                .overlay {
                    Capsule().stroke(ink.opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(is3DView ? t("view_3d") : t("view_2d"))
    }

    private var lookMenu: some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) {
                showLookPanel.toggle()
            }
            HapticsService.select(enabled: settings.hapticsEnabled)
        } label: {
            Image(systemName: showLookPanel ? "gearshape.fill" : "gearshape")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(hudChromeInk)
                .frame(width: 32, height: 32)
                .background(hudChromeFill, in: Circle())
                .overlay {
                    Circle().stroke(hudChromeInk.opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("look_settings"))
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 6) {
                Color.clear
                    .frame(width: 32, height: 32)
                    .allowsHitTesting(false)
                ZStack(alignment: .topTrailing) {
                    if showLookPanel {
                        VStack(alignment: .trailing, spacing: 6) {
                            lookPanelChips
                        }
                        .fixedSize()
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(width: 180, height: lookPanelClipHeight, alignment: .topTrailing)
                .clipped()
                .allowsHitTesting(showLookPanel)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showLookPanel)
    }

    private var lookPanelClipHeight: CGFloat {
        skin == .sakura ? 76 : 152
    }

    @ViewBuilder
    private var lookPanelChips: some View {
        if skin == .sakura {
            lookChip(t(sakuraLook == .mono ? "sakura_look_mono" : "sakura_look_color")) {
                sakuraLook.cycle()
                applyBoardLook()
                scene.syncBoard(game.model, winningLine: nil)
            }
            lookChip(t(sakuraTabletTitleKey)) {
                sakuraTablet.cycle()
                applyBoardSurfaces()
            }
        } else {
            lookChip(isDark ? t("look_dark") : t("look_light")) {
                settings.boardDark.toggle()
                applyBoardLook()
            }
            lookChip(settings.sealPalette == .mono ? t("seal_mono") : t("seal_classic")) {
                settings.sealPalette.cycle()
                applyBoardLook()
                scene.syncBoard(game.model, winningLine: nil)
            }
            lookChip(t(tabletTitleKey)) {
                settings.tabletFinish.cycle()
                applyBoardSurfaces()
            }
            lookChip(t(tableTitleKey)) {
                settings.tableFinish.cycle()
                applyBoardSurfaces()
            }
        }
    }

    private func lookChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticsService.select(enabled: settings.hapticsEnabled)
        } label: {
            Text(title)
                .font(.system(.caption, design: .serif).weight(.semibold))
                .foregroundStyle(lookChipInk)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(lookChipFill, in: Capsule())
                .overlay {
                    Capsule().stroke(lookChipInk.opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var isDark: Bool { skin == .sakura ? true : settings.boardDark }
    private var resultScheme: ColorScheme {
        if skin == .sakura {
            return sakuraLook == .color ? .light : .dark
        }
        return isDark ? .dark : .light
    }
    private var usesSakuraSurfaces: Bool { skin == .sakura }
    private var activeSeals: SealPalette {
        if skin == .sakura {
            return sakuraLook == .mono ? .mono : .classic
        }
        return settings.sealPalette
    }
    private var canvas: Color { Theme.canvas(dark: isDark) }
    private var ink: Color {
        if skin == .sakura {
            return isDark ? Color(white: 0.96) : Color(white: 0.08)
        }
        return Theme.ink(dark: isDark)
    }
    private var overlayInk: Color {
        if skin == .sakura {
            return Color(white: 1)
        }
        return ink
    }
    private var boardInk: Color {
        if skin == .sakura {
            return isDark ? Color(white: 0.96) : Color(white: 0.08)
        }
        return Theme.ink(dark: isDark)
    }
    private var textHalo: Color {
        guard skin == .sakura else { return .clear }
        return isDark ? Color.black.opacity(0.55) : Color.white.opacity(0.8)
    }
    private var overlayHalo: Color {
        guard skin == .sakura else { return .clear }
        return Color.black.opacity(0.55)
    }
    private var chromeFill: Color {
        if skin == .sakura {
            return isDark ? Color.white.opacity(0.14) : Color.white.opacity(0.55)
        }
        return Theme.chipFill(dark: isDark)
    }
    private var usesWhiteSealChrome: Bool { skin == .sakura && sakuraLook == .mono }
    private var lookChipFill: Color {
        if skin == .sakura, sakuraLook == .mono {
            return Theme.waxWhite
        }
        return chromeFill
    }
    private var lookChipInk: Color {
        if skin == .sakura, sakuraLook == .mono {
            return Theme.ink
        }
        return ink
    }
    private var hudChromeFill: Color {
        if skin == .sakura, sakuraLook == .mono {
            return Theme.waxBlack
        }
        return chromeFill
    }
    private var hudChromeInk: Color {
        if skin == .sakura, sakuraLook == .mono {
            return Theme.cream
        }
        return skin == .sakura ? Theme.ink(dark: true) : ink
    }
    private var bannerFont: Font { .system(.body, design: .serif).weight(.medium) }
    private var hudMeterFont: Font { .system(.title2, design: .serif).weight(.medium) }
    private var turnTimerColor: Color {
        if turnSecondsLeft <= 5 { return Theme.waxRed }
        return usesWhiteSealChrome ? lookChipInk : ink
    }

    private var currentColor: Color {
        Theme.seal(game.currentPlayer, palette: activeSeals, skin: usesSakuraSurfaces ? .sakura : .classic)
    }

    private var titleColor: Color {
        if activeSeals == .mono {
            if isDark, game.currentPlayer == .red { return ink }
            if !isDark, game.currentPlayer == .indigo { return ink }
        }
        return currentColor
    }

    private var onSeal: Color {
        if activeSeals == .mono, game.currentPlayer == .indigo {
            return Theme.ink
        }
        return Theme.cream
    }

    private var sealMotif: Color {
        if activeSeals == .mono, game.currentPlayer == .indigo {
            return Theme.waxBlack
        }
        return Theme.gold
    }

    private var sealOutline: Color? {
        guard activeSeals == .mono else { return nil }
        if isDark, game.currentPlayer == .red {
            return ink.opacity(0.7)
        }
        if !isDark, game.currentPlayer == .indigo {
            return ink.opacity(0.4)
        }
        return nil
    }

    private var sakuraTabletTitleKey: String.LocalizationValue {
        switch sakuraTablet {
        case .grey: "sakura_tablet_grey"
        case .white: "sakura_tablet_white"
        case .taupe: "sakura_tablet_taupe"
        case .charcoal: "sakura_tablet_charcoal"
        case .paper: "sakura_tablet_paper"
        case .glass: "sakura_tablet_glass"
        }
    }

    private var tableTitleKey: String.LocalizationValue {
        switch settings.tableFinish {
        case .walnut: "table_walnut"
        case .ebony: "table_ebony"
        case .oak: "table_oak"
        }
    }

    private var tabletTitleKey: String.LocalizationValue {
        switch settings.tabletFinish {
        case .granite: "tablet_granite"
        case .slate: "tablet_slate"
        case .sand: "tablet_sand"
        }
    }

    private var turnTitle: String {
        if game.mode == .gameCenter {
            return isLocalTurn ? t("turn_you") : t("turn_waiting")
        }
        if activeSeals == .mono {
            return game.currentPlayer == .red ? t("turn_black") : t("turn_white")
        }
        return game.currentPlayer == .red ? t("turn_red") : t("turn_indigo")
    }

    private func moveLine(_ move: LastMove) -> String {
        let player: String
        if activeSeals == .mono {
            player = move.player == .red ? t("player_black") : t("player_white")
        } else {
            player = move.player == .red ? t("player_red") : t("player_indigo")
        }
        let cell = cellName(move.position)
        guard let quadrant = move.quadrant, let clockwise = move.clockwise else {
            return "\(player)  ·  \(cell)"
        }
        let turn = clockwise ? t("last_right") : t("last_left")
        return "\(player)  ·  \(cell)  ·  \(quadrantName(quadrant)) \(turn)"
    }

    private func logFont(index: Int) -> Font {
        let weight: Font.Weight = index == 0 ? .medium : .regular
        if skin == .sakura {
            return .system(size: overlayTypeSize, weight: weight, design: .serif)
        }
        return .system(.subheadline, design: .serif).weight(weight)
    }

    private func moveLogOpacity(_ index: Int) -> Double {
        if skin == .sakura {
            switch index {
            case 0: 0.80
            case 1: 0.72
            case 2: 0.5
            default: 0.32
            }
        } else {
            switch index {
            case 0: 0.75
            case 1: 0.48
            case 2: 0.30
            default: 0.16
            }
        }
    }

    private func cellName(_ position: Position) -> String {
        let column = Character(UnicodeScalar(65 + position.col)!)
        return "\(column)\(position.row + 1)"
    }

    private func quadrantName(_ quadrant: Quadrant) -> String {
        switch quadrant {
        case .nw: t("quad_nw")
        case .ne: t("quad_ne")
        case .sw: t("quad_sw")
        case .se: t("quad_se")
        }
    }

    private var turnTimer: some View {
        Text("\(max(turnSecondsLeft, 1))")
            .font(hudMeterFont)
            .monospacedDigit()
            .foregroundStyle(turnTimerColor)
            .frame(minWidth: 28, alignment: .center)
            .padding(.horizontal, usesWhiteSealChrome ? 8 : 0)
            .padding(.vertical, usesWhiteSealChrome ? 2 : 0)
            .background(usesWhiteSealChrome ? lookChipFill : Color.clear, in: Capsule())
            .overlay {
                if usesWhiteSealChrome {
                    Capsule().stroke(lookChipInk.opacity(0.35), lineWidth: 1)
                }
            }
            .opacity(isHumanTurn && turnSecondsLeft > 0 ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: turnSecondsLeft)
            .accessibilityLabel(t("turn_timer"))
            .accessibilityValue("\(turnSecondsLeft)")
            .accessibilityHidden(!(isHumanTurn && turnSecondsLeft > 0))
    }

    private var turnSteps: some View {
        HStack(spacing: 8) {
            stepChip(t("step_place"), active: game.phase == .place)
            Image(systemName: "arrow.right")
                .font(.system(.subheadline, design: .serif).weight(.medium))
                .foregroundStyle(ink.opacity(0.35))
            stepChip(t("step_rotate"), active: game.phase == .rotate)
        }
        .animation(.easeInOut(duration: 0.28), value: game.phase)
    }

    private func stepChip(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .serif).weight(.medium))
            .foregroundStyle(active ? onSeal : ink.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(active ? currentColor : ink.opacity(isDark ? 0.16 : 0.08), in: Capsule())
    }

    private var isAIThinking: Bool {
        if case .ai = game.mode, game.currentPlayer == .indigo { return true }
        return false
    }

    private var isLocalPassPlay: Bool {
        if case .local = game.mode { return true }
        return false
    }

    private var locksTo2D: Bool { isLocalPassPlay && skin != .sakura }
    private var showsTurnTimer: Bool { !isLocalPassPlay || skin == .sakura }
    private var showsPerspectiveChip: Bool { !isLocalPassPlay || skin == .sakura }

    private var isLocalTurn: Bool {
        guard let match = gameCenter.activeMatch else { return true }
        return gameCenter.isLocalTurn(match)
    }

    private var isHumanTurn: Bool {
        guard game.status == .playing else { return false }
        switch game.mode {
        case .local:
            return true
        case .ai:
            return game.currentPlayer == .red
        case .gameCenter:
            guard let match = gameCenter.activeMatch else { return false }
            return gameCenter.isLocalTurn(match) && game.currentPlayer == gameCenter.localPlayerColor(in: match)
        }
    }

    private var canAct: Bool {
        isHumanTurn && !busy
    }

    private func configureScene() {
        scene.onCellTap = { position in
            handlePlace(position)
        }
        scene.onQuadrantTap = { quadrant in
            selectedQuadrant = quadrant
            if quadrant != nil {
                HapticsService.select(enabled: settings.hapticsEnabled)
            }
        }
        scene.onRotateGesture = { quadrant, clockwise in
            applyRotation(quadrant: quadrant, clockwise: clockwise)
        }
        scene.resetTabletOrientation()
        applyBoardLook()
        scene.syncBoard(game.model, winningLine: nil)
        scene.setPerspective3D(locksTo2D ? false : is3DView)
        refreshInteraction()
        if shouldStartAI {
            Task { await playAI() }
        } else {
            beginNextTurnClock()
        }
    }

    private var shouldStartAI: Bool {
        if case .ai = game.mode { return game.currentPlayer == .indigo && game.status == .playing }
        return false
    }

    private func refreshInteraction() {
        scene.setInteraction(canPlace: canAct && game.phase == .place, canSelectQuadrant: canAct && game.phase == .rotate)
        if game.phase != .rotate {
            selectedQuadrant = nil
        }
    }

    private func handlePlace(_ position: Position) {
        guard canAct, game.phase == .place else { return }
        let player = game.currentPlayer
        guard game.place(at: position) else { return }
        WaxlinePerf.event("place.tap", "skin=\(skin)")
        scene.dropSeal(at: position, player: player)
        HapticsService.place(enabled: settings.hapticsEnabled)
        SoundService.place(enabled: settings.soundEnabled)
        if game.isFinished {
            finishTurnIfNeeded()
            return
        }
        refreshInteraction()
    }

    private func applyRotation(quadrant: Quadrant, clockwise: Bool) {
        guard canAct else { return }
        busy = true
        var preview = game.model
        guard preview.rotate(quadrant: quadrant, clockwise: clockwise) else {
            busy = false
            return
        }
        HapticsService.rotate(enabled: settings.hapticsEnabled)
        SoundService.rotate(enabled: settings.soundEnabled)
        scene.animateRotation(quadrant: quadrant, clockwise: clockwise, model: preview) {
            _ = game.rotate(quadrant: quadrant, clockwise: clockwise)
            selectedQuadrant = nil
            busy = false
            finishTurnIfNeeded()
            refreshInteraction()
            if shouldStartAI {
                stopTurnTimer()
                Task { await playAI() }
            } else {
                beginNextTurnClock()
            }
        }
    }

    private func finishTurnIfNeeded() {
        if game.mode == .gameCenter, let match = gameCenter.activeMatch {
            let shouldSend = game.isFinished || game.phase == .place
            if shouldSend {
                Task { await gameCenter.submitTurn(match: match, model: game.model) }
            }
        }
    }

    private func applyBoardSurfaces() {
        scene.applySurfaces(
            table: settings.tableFinish,
            tablet: settings.tabletFinish,
            skin: skin,
            sakuraTablet: sakuraTablet,
            showTable: skin != .sakura
        )
    }

    private func applyBoardLook() {
        scene.applyLook(
            dark: isDark,
            seals: activeSeals,
            table: settings.tableFinish,
            tablet: settings.tabletFinish,
            clearCanvas: skin == .sakura,
            skin: skin,
            sakuraTablet: sakuraTablet,
            showTable: skin != .sakura
        )
    }

    private func highlightWin() {
        if case .won(_, let line) = game.status {
            scene.syncBoard(game.model, winningLine: line)
        }
    }

    private func replay() {
        showResult = false
        game.reset()
        selectedQuadrant = nil
        busy = false
        scene.abandonTabletDrag()
        scene.resetTabletOrientation()
        scene.syncBoard(game.model, winningLine: nil)
        refreshInteraction()
        beginNextTurnClock()
    }

    private func reloadRemoteMatch() {
        guard game.mode == .gameCenter, let match = gameCenter.activeMatch else { return }
        game.replace(with: gameCenter.model(from: match))
        scene.syncBoard(game.model, winningLine: {
            if case .won(_, let line) = game.status { return line }
            return nil
        }())
        refreshInteraction()
        if isHumanTurn {
            if timerTask == nil {
                startTurnTimer()
            }
        } else {
            stopTurnTimer()
        }
    }

    private func playAI() async {
        guard case .ai(let level) = game.mode, game.currentPlayer == .indigo, game.status == .playing else { return }
        scene.abandonTabletDrag()
        busy = true
        scene.setInteraction(canPlace: false, canSelectQuadrant: false)
        try? await Task.sleep(for: .milliseconds(380))
        let place = GameAI.choosePlacement(model: game.model, level: level)
        let placer = game.currentPlayer
        _ = game.place(at: place)
        scene.dropSeal(at: place, player: placer)
        HapticsService.place(enabled: settings.hapticsEnabled)
        SoundService.place(enabled: settings.soundEnabled)
        if game.isFinished {
            busy = false
            return
        }
        try? await Task.sleep(for: .milliseconds(420))
        let rotation = GameAI.chooseRotation(model: game.model, level: level)
        var preview = game.model
        _ = preview.rotate(quadrant: rotation.0, clockwise: rotation.1)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            scene.animateRotation(quadrant: rotation.0, clockwise: rotation.1, model: preview) {
                _ = game.rotate(quadrant: rotation.0, clockwise: rotation.1)
                continuation.resume()
            }
        }
        busy = false
        refreshInteraction()
        beginNextTurnClock()
    }

    private func beginNextTurnClock() {
        stopTurnTimer()
        guard showsTurnTimer, game.status == .playing, isHumanTurn else { return }
        startTurnTimer()
    }

    private func startTurnTimer() {
        timerTask?.cancel()
        turnSecondsLeft = turnTimeLimit
        guard isHumanTurn else { return }
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                if busy || showLookPanel { continue }
                guard isHumanTurn, game.status == .playing else { return }
                if turnSecondsLeft <= 1 {
                    turnSecondsLeft = 0
                    await playTimeoutMove()
                    return
                }
                turnSecondsLeft -= 1
            }
        }
    }

    private func stopTurnTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func playTimeoutMove() async {
        timerTask = nil
        guard isHumanTurn, game.status == .playing, !busy else { return }
        scene.abandonTabletDrag()
        busy = true
        scene.setInteraction(canPlace: false, canSelectQuadrant: false)

        if game.phase == .place {
            let place = GameAI.choosePlacement(model: game.model, level: .easy)
            let placer = game.currentPlayer
            _ = game.place(at: place)
            scene.dropSeal(at: place, player: placer)
            HapticsService.place(enabled: settings.hapticsEnabled)
            SoundService.place(enabled: settings.soundEnabled)
            if game.isFinished {
                busy = false
                finishTurnIfNeeded()
                return
            }
            try? await Task.sleep(for: .milliseconds(280))
        }

        if game.phase == .rotate, game.status == .playing {
            let rotation = GameAI.chooseRotation(model: game.model, level: .easy)
            var preview = game.model
            _ = preview.rotate(quadrant: rotation.0, clockwise: rotation.1)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                scene.animateRotation(quadrant: rotation.0, clockwise: rotation.1, model: preview) {
                    _ = game.rotate(quadrant: rotation.0, clockwise: rotation.1)
                    continuation.resume()
                }
            }
            HapticsService.rotate(enabled: settings.hapticsEnabled)
            SoundService.rotate(enabled: settings.soundEnabled)
        }

        busy = false
        finishTurnIfNeeded()
        refreshInteraction()
        if shouldStartAI {
            stopTurnTimer()
            Task { await playAI() }
        } else {
            beginNextTurnClock()
        }
    }
}

private struct OverlayReadable: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .shadow(color: .black.opacity(0.95), radius: 0, y: 1)
                .shadow(color: .black.opacity(0.8), radius: 3)
                .shadow(color: .black.opacity(0.45), radius: 8)
        } else {
            content
        }
    }
}

private struct CornerBrackets: Shape {
    var cornerRadius: CGFloat
    var length: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, length)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}

private struct BoardRectKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
