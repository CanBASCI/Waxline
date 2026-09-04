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
    @State private var sakuraDark = false
    @State private var sakuraTable: SakuraTableTheme = .oak
    @State private var sakuraTablet: SakuraTabletTheme = .glass
    @State private var sakuraShowsTable = false
    @State private var resultTask: Task<Void, Never>?
    @State private var timerTask: Task<Void, Never>?
    @State private var turnSecondsLeft = 15
    @State private var boardRect: CGRect = .zero
    @State private var tableSpinActive = false
    private let boardGutter: CGFloat = 30
    private let boardBottomTrim: CGFloat = 40
    private let turnTimeLimit = 15

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            turnBanner
            BoardSceneView(controller: scene)
                .aspectRatio(0.72, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, -boardBottomTrim)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    CornerBrackets(cornerRadius: 12, length: 18)
                        .stroke(ink.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
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
                    boardStatus
                }
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: BoardRectKey.self, value: geo.frame(in: .named("gameCanvas")))
                    }
                }
                .padding(.top, 0)
                .padding(.bottom, boardGutter)
            footer
            Spacer(minLength: 0)
        }
        .coordinateSpace(name: "gameCanvas")
        .onPreferenceChange(BoardRectKey.self) { boardRect = $0 }
        .contentShape(Rectangle())
        .simultaneousGesture(tableSpinGesture)
        .background {
            if skin == .sakura {
                GameLoopBackdrop(resource: "gamescreensakuravideo_2", ext: "mov")
            } else {
                canvas.ignoresSafeArea()
            }
        }
        .preferredColorScheme(isDark ? .dark : .light)
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
            ResultSheet(game: game, skin: usesSakuraSurfaces ? .sakura : .classic, onAgain: replay, onMenu: onExit)
                .presentationDetents([.height(240)])
        }
        .onDisappear {
            resultTask?.cancel()
            stopTurnTimer()
            finishTableSpin()
        }
    }

    private var header: some View {
        HStack {
            Button(t("menu")) { onExit() }
                .font(bannerFont)
                .foregroundStyle(ink)
            Spacer(minLength: 8)
            lookMenu
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 0)
        .shadow(color: textHalo, radius: skin == .sakura ? 8 : 0)
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
                    .foregroundStyle(titleColor)
                Spacer(minLength: 8)
                if showsTurnTimer {
                    Text("\(max(turnSecondsLeft, 1))")
                        .font(.system(.title2, design: .serif).weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(turnTimerColor)
                        .frame(minWidth: 28, alignment: .center)
                        .opacity(isHumanTurn && turnSecondsLeft > 0 ? 1 : 0)
                        .animation(.easeInOut(duration: 0.18), value: turnSecondsLeft)
                        .accessibilityLabel(t("turn_timer"))
                        .accessibilityValue("\(turnSecondsLeft)")
                        .accessibilityHidden(!(isHumanTurn && turnSecondsLeft > 0))
                }
            }
            HStack(alignment: .center, spacing: 8) {
                if game.status == .playing {
                    turnSteps
                }
                Spacer(minLength: 8)
                if showsPerspectiveChip {
                    perspectiveChip
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, boardGutter)
        .padding(.bottom, boardGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: textHalo, radius: skin == .sakura ? 8 : 0)
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(game.moveLog.enumerated()), id: \.element.id) { index, move in
                    Text(moveLine(move))
                        .font(.system(.subheadline, design: .serif).weight(index == 0 ? .medium : .regular))
                        .foregroundStyle(ink.opacity(moveLogOpacity(index)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            sealReserve
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .shadow(color: textHalo, radius: skin == .sakura ? 8 : 0)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(t("last_move"))
        .accessibilityValue(game.moveLog.map(moveLine).joined(separator: ", "))
    }

    private var sealReserve: some View {
        VStack(alignment: .trailing, spacing: 8) {
            sealPiles(for: .red)
            sealPiles(for: .indigo)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("seal_reserve"))
        .accessibilityValue(
            "\(remainingSeals(for: .red)), \(remainingSeals(for: .indigo))"
        )
    }

    private func sealPiles(for player: Player) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { pile in
                sealPile(count: pileCount(for: player, pile: pile), player: player)
            }
        }
    }

    private func sealPile(count: Int, player: Player) -> some View {
        let size: CGFloat = 16
        let step: CGFloat = 3
        return ZStack(alignment: .bottom) {
            ForEach(0..<count, id: \.self) { index in
                SealMark(
                    color: Theme.seal(player, palette: settings.sealPalette, skin: usesSakuraSurfaces ? .sakura : .classic),
                    motif: reserveMotif(player),
                    outline: stackEdge(for: player),
                    outlineWidth: 1.2
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
        return min(6, max(0, remaining - pile * 6))
    }

    private func reserveMotif(_ player: Player) -> Color {
        if settings.sealPalette == .mono, player == .indigo {
            return Theme.waxBlack
        }
        return Theme.gold
    }

    private func stackEdge(for player: Player) -> Color {
        let isWhite = settings.sealPalette == .mono && player == .indigo
        return isWhite ? Theme.waxBlack : (skin == .sakura ? Color.white : Theme.cream)
    }

    private var boardStatus: some View {
        Group {
            if let message = boardStatusText {
                Text(message)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(ink.opacity(0.7))
                    .shadow(color: textHalo, radius: skin == .sakura ? 6 : 0)
                    .padding(.bottom, 16)
            }
        }
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
            return t(settings.sealPalette == .mono ? "waiting_white" : "waiting_ai")
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
            is3DView.toggle()
            scene.setPerspective3D(is3DView)
            HapticsService.select(enabled: settings.hapticsEnabled)
        } label: {
            Text(is3DView ? t("view_3d") : t("view_2d"))
                .font(.system(.subheadline, design: .serif).weight(.medium))
                .foregroundStyle(ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay {
                    Capsule().stroke(ink.opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(is3DView ? t("view_3d") : t("view_2d"))
    }

    private var lookMenu: some View {
        HStack(alignment: .center, spacing: 6) {
            ZStack(alignment: .trailing) {
                if showLookPanel {
                    HStack(spacing: 6) {
                        if skin == .sakura {
                            lookChip(sakuraDark ? t("look_dark") : t("look_light")) {
                                sakuraDark.toggle()
                                applyBoardLook()
                                scene.syncBoard(game.model, winningLine: nil)
                            }
                            lookChip(t(sakuraTableTitleKey)) {
                                sakuraTable.cycle()
                                applyBoardSurfaces()
                            }
                            lookChip(t(sakuraTabletTitleKey)) {
                                sakuraTablet.cycle()
                                applyBoardSurfaces()
                            }
                            lookChip(sakuraShowsTable ? t("sakura_table_hide") : t("sakura_table_show")) {
                                sakuraShowsTable.toggle()
                                WaxlinePerf.event(sakuraShowsTable ? "table.show" : "table.hide")
                                scene.setTableVisible(sakuraShowsTable)
                            }
                        } else {
                            lookChip(isDark ? t("look_dark") : t("look_light")) {
                                settings.boardDark.toggle()
                                applyBoardLook()
                            }
                        }
                        lookChip(settings.sealPalette == .mono ? t("seal_mono") : t("seal_classic")) {
                            settings.sealPalette.cycle()
                            applyBoardLook()
                            scene.syncBoard(game.model, winningLine: nil)
                        }
                        if skin != .sakura {
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
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .clipped()

            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    showLookPanel.toggle()
                }
                HapticsService.select(enabled: settings.hapticsEnabled)
            } label: {
                Image(systemName: showLookPanel ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 32, height: 32)
                    .background(chromeFill, in: Circle())
                    .overlay {
                        Circle().stroke(ink.opacity(0.35), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("look_settings"))
        }
        .animation(.easeOut(duration: 0.25), value: showLookPanel)
    }

    private func lookChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticsService.select(enabled: settings.hapticsEnabled)
        } label: {
            Text(title)
                .font(.system(.caption, design: .serif).weight(.semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(chromeFill, in: Capsule())
                .overlay {
                    Capsule().stroke(ink.opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var isDark: Bool { skin == .sakura ? sakuraDark : settings.boardDark }
    private var usesSakuraSurfaces: Bool { skin == .sakura }
    private var canvas: Color { Theme.canvas(dark: isDark) }
    private var ink: Color {
        if skin == .sakura {
            return isDark ? Color(white: 0.96) : Color(white: 0.08)
        }
        return Theme.ink(dark: isDark)
    }
    private var textHalo: Color {
        guard skin == .sakura else { return .clear }
        return isDark ? Color.black.opacity(0.55) : Color.white.opacity(0.8)
    }
    private var chromeFill: Color {
        if skin == .sakura {
            return isDark ? Color.white.opacity(0.14) : Color.white.opacity(0.55)
        }
        return Theme.chipFill(dark: isDark)
    }
    private var bannerFont: Font { .system(.body, design: .serif).weight(.medium) }
    private var turnTimerColor: Color {
        turnSecondsLeft <= 5 ? Theme.waxRed : ink
    }

    private var currentColor: Color {
        Theme.seal(game.currentPlayer, palette: settings.sealPalette, skin: usesSakuraSurfaces ? .sakura : .classic)
    }

    private var titleColor: Color {
        if settings.sealPalette == .mono {
            if isDark, game.currentPlayer == .red { return ink }
            if !isDark, game.currentPlayer == .indigo { return ink }
        }
        return currentColor
    }

    private var onSeal: Color {
        if settings.sealPalette == .mono, game.currentPlayer == .indigo {
            return Theme.ink
        }
        return Theme.cream
    }

    private var sealMotif: Color {
        if settings.sealPalette == .mono, game.currentPlayer == .indigo {
            return Theme.waxBlack
        }
        return Theme.gold
    }

    private var sealOutline: Color? {
        guard settings.sealPalette == .mono else { return nil }
        if isDark, game.currentPlayer == .red {
            return ink.opacity(0.7)
        }
        if !isDark, game.currentPlayer == .indigo {
            return ink.opacity(0.4)
        }
        return nil
    }

    private var sakuraTableTitleKey: String.LocalizationValue {
        switch sakuraTable {
        case .oak: "sakura_table_oak"
        case .honey: "sakura_table_honey"
        case .plank: "sakura_table_plank"
        case .cedar: "sakura_table_cedar"
        }
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
        if settings.sealPalette == .mono {
            return game.currentPlayer == .red ? t("turn_black") : t("turn_white")
        }
        return game.currentPlayer == .red ? t("turn_red") : t("turn_indigo")
    }

    private func moveLine(_ move: LastMove) -> String {
        let player: String
        if settings.sealPalette == .mono {
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

    private func moveLogOpacity(_ index: Int) -> Double {
        switch index {
        case 0: 0.75
        case 1: 0.48
        case 2: 0.30
        default: 0.16
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
        WaxlinePerf.event("place.tap", "skin=\(skin) table=\(sakuraShowsTable)")
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
            sakuraTable: sakuraTable,
            sakuraTablet: sakuraTablet,
            showTable: sakuraShowsTable
        )
    }

    private func applyBoardLook() {
        scene.applyLook(
            dark: isDark,
            seals: settings.sealPalette,
            table: settings.tableFinish,
            tablet: settings.tabletFinish,
            clearCanvas: skin == .sakura,
            skin: skin,
            sakuraTable: sakuraTable,
            sakuraTablet: sakuraTablet,
            showTable: sakuraShowsTable
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
