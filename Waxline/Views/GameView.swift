import SwiftUI
import UIKit

struct GameView: View {
    @Bindable var game: GameState
    var onExit: () -> Void
    var onPreserveSeries: () -> Void = {}

    @Environment(SettingsStore.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(\.scenePhase) private var scenePhase
    @State private var scene = BoardSceneController()
    @State private var selectedQuadrant: Quadrant?
    @State private var busy = false
    @State private var showResult = false
    @State private var confirmLeave = false
    @State private var showInviteDeclined = false
    @State private var is3DView = false
    private var sakuraLook: SakuraLook {
        get { settings.sakuraLook }
        nonmutating set { settings.sakuraLook = newValue }
    }
    private var sakuraTablet: SakuraTabletTheme {
        sakuraLook == .color ? .blossom : .charcoal
    }
    @State private var resultTask: Task<Void, Never>?
    @State private var timerTask: Task<Void, Never>?
    @State private var remotePlaybackTask: Task<Void, Never>?
    @State private var inviteWatchTask: Task<Void, Never>?
    @State private var opponentPhoto: UIImage?
    @State private var turnSecondsLeft = 15
    @State private var canvasSize = CGSize(width: 390, height: 844)
    private var isCompactCanvas: Bool { canvasSize.height < 720 }
    private var boardGutter: CGFloat { isCompactCanvas ? 16 : 30 }
    private var footerSlotHeight: CGFloat { isCompactCanvas ? 88 : 108 }
    private var overlayTypeSize: CGFloat { 18 }
    private var sakuraBoardSide: CGFloat {
        let chrome: CGFloat = 12 + 32
            + boardGutter + 68 + 8
            + 44
            + 36
            + 18 + footerSlotHeight + 8
            + boardGutter
        return min(canvasSize.width, max(200, canvasSize.height - chrome))
    }
    private let sealBaseSize: CGFloat = 16
    private let sealBaseStep: CGFloat = 3
    private let sealBaseRowGap: CGFloat = 8
    private let sealBasePileGap: CGFloat = 5
    private let turnTimeLimit = 15

    private var sealScale: CGFloat {
        let fullHeight = (sealBaseSize + sealBaseStep * 5) * 2 + sealBaseRowGap
        return footerSlotHeight / fullHeight
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
        .background {
            ZStack(alignment: .bottom) {
                GameLoopBackdrop(
                    resource: sakuraLook == .color ? "gameplaycolorfulbackgroundvideo" : "gamescreensakuravideo_2",
                    ext: "mov"
                )
                .id(sakuraLook)
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
        }
        .preferredColorScheme(.dark)
        .onAppear {
            configureScene()
            startInviteWatchIfNeeded()
        }
        .onChange(of: waitingForOpponent) { _, _ in
            startInviteWatchIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard waitingForOpponent else { return }
            if phase == .background {
                Task { await gameCenter.pulseWaitingHeartbeat(suspended: true) }
            } else if phase == .active {
                Task { await gameCenter.pulseWaitingHeartbeat(suspended: false) }
            }
        }
        .onChange(of: game.status) { oldStatus, newStatus in
            if oldStatus == .playing, newStatus != .playing {
                game.recordSeriesResult(you: seriesYou)
            }
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
            remotePlaybackTask?.cancel()
            remotePlaybackTask = Task { await applyRemoteMatch() }
            Task { await loadOpponentIdentity() }
        }
        .task(id: gameCenter.sessionKey) {
            await loadOpponentIdentity()
        }
        .sheet(isPresented: $showResult) {
            ResultSheet(game: game, seals: activeSeals, onAgain: replay, onMenu: leaveAndExit)
                .environment(\.colorScheme, sakuraLook.colorScheme)
                .preferredColorScheme(sakuraLook.colorScheme)
        }
        .alert(t("gc_leave_title"), isPresented: $confirmLeave) {
            Button(t("gc_leave_confirm"), role: .destructive, action: leaveAndExit)
            Button(t("gc_cancel"), role: .cancel) {}
        } message: {
            Text(t("gc_leave_message"))
        }
        .alert(t("gc_invite_declined_title"), isPresented: $showInviteDeclined) {
            Button(t("gc_invite_declined_ok"), action: leaveAfterDecline)
        } message: {
            Text(t("gc_invite_declined_message"))
        }
        .onDisappear {
            resultTask?.cancel()
            remotePlaybackTask?.cancel()
            inviteWatchTask?.cancel()
            stopTurnTimer()
        }
    }

    private var playStack: some View {
        VStack(spacing: 0) {
            header
            turnBanner
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            HStack(alignment: .center, spacing: 8) {
                turnTimer
                Spacer(minLength: 8)
                perspectiveChip
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            BoardSceneView(controller: scene)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: sakuraBoardSide, height: sakuraBoardSide)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    CornerBrackets(cornerRadius: 12, length: 18)
                        .stroke(boardInk.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .padding(1)
                        .allowsHitTesting(false)
                }
                .padding(.top, 0)
                .padding(.bottom, boardGutter)
            footer
        }
    }

    private var header: some View {
        HStack {
            Button(action: requestLeave) {
                Text(t("menu"))
                    .font(bannerFont)
                    .foregroundStyle(hudChromeInk)
                    .padding(.horizontal, 13.5)
                    .frame(height: hudChromeHeight)
                    .background(hudChromeFill, in: Capsule())
                    .overlay {
                        Capsule().stroke(hudChromeInk.opacity(0.35), lineWidth: 1)
                    }
                    .shadow(color: textHalo, radius: 8)
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.22), value: sakuraLook)
            Spacer(minLength: 8)
            lookToggle
                .shadow(color: textHalo, radius: 8)
                .animation(.easeInOut(duration: 0.22), value: sakuraLook)
        }
        .zIndex(1)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 0)
    }

    private var turnBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 9) {
                SealMark(
                    color: currentColor,
                    motif: sealMotif,
                    outline: hudStepStroke(active: true),
                    outlineWidth: 1
                )
                .frame(width: turnSealSize, height: turnSealSize)
                Text(turnTitle)
                    .font(turnTitleFont)
                    .foregroundStyle(overlayCopy)
                    .modifier(OverlayReadable())
            }
            HStack(alignment: .center, spacing: 8) {
                if game.status == .playing, !waitingForOpponent {
                    turnSteps
                }
                Spacer(minLength: 8)
            }
            if showsOpponentIdentity {
                opponentIdentityMark
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, boardGutter)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: textHalo, radius: 8)
    }

    private var showsOpponentIdentity: Bool {
        game.mode == .gameCenter
    }

    private var opponentIdentityMark: some View {
        HStack(alignment: .center, spacing: 9) {
            Button {
                HapticsService.select(enabled: settings.hapticsEnabled)
                gameCenter.presentOpponentProfile()
            } label: {
                HStack(alignment: .center, spacing: 9) {
                    opponentPhotoMark
                    Text(gameCenter.opponentDisplayName)
                        .font(turnTitleFont)
                        .foregroundStyle(overlayCopy)
                        .modifier(OverlayReadable())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .opacity(opponentPhotoDimmed ? opponentPhotoDimOpacity : 1)
                        .animation(.easeInOut(duration: 0.28), value: opponentPhotoDimmed)
                }
            }
            .buttonStyle(.plain)
            .disabled(gameCenter.opponentPlayer() == nil)
            .accessibilityLabel(gameCenter.opponentDisplayName)
            .accessibilityHint(t("gc_player_profile"))
            .accessibilityValue(opponentPhotoDimmed ? t("turn_you") : t("turn_waiting"))
            Spacer(minLength: 0)
        }
    }

    private var opponentPhotoMark: some View {
        Group {
            if let opponentPhoto {
                Image(uiImage: opponentPhoto)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(overlayCopy.opacity(0.85))
            }
        }
        .frame(width: hudChromeHeight, height: hudChromeHeight)
        .clipShape(Circle())
        .grayscale(sakuraLook == .mono ? 1 : 0)
        .overlay {
            Circle()
                .fill(Color.black.opacity(sakuraLook == .mono && opponentPhotoDimmed ? 0.62 : 0))
        }
        .overlay {
            Circle().stroke(
                hudStepStroke(active: !opponentPhotoDimmed),
                lineWidth: 1
            )
        }
        .opacity(opponentPhotoDimmed ? opponentPhotoDimOpacity : 1)
        .animation(.easeInOut(duration: 0.28), value: opponentPhotoDimmed)
        .accessibilityHidden(true)
    }

    private var opponentPhotoDimmed: Bool {
        game.status == .playing && isLocalTurn && !waitingForOpponent
    }

    private var opponentPhotoDimOpacity: CGFloat {
        sakuraLook == .mono ? 0.42 : 0.38
    }

    private func loadOpponentIdentity() async {
        opponentPhoto = await gameCenter.loadOpponentPhoto()
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            footerHint
            sealReserve
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 2)
        .shadow(color: overlayHalo, radius: 8)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(boardStatusText ?? t("seal_reserve"))
    }

    private var seriesMaxWidth: CGFloat {
        max(96, canvasSize.width / 2 - 20)
    }

    private var seriesSealSize: CGFloat {
        let hintBlock = overlayTypeSize * 1.4 + 8
        let heightBudget = min(footerSlotHeight * 0.42, max(26, footerSlotHeight - hintBlock))
        let widthFactor: CGFloat = game.series.draws > 0 ? 7.8 : 5.2
        return min(heightBudget, seriesMaxWidth / widthFactor)
    }

    private var footerHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            SeriesScoreRow(
                series: game.series,
                seals: activeSeals,
                you: seriesYou,
                sealSize: seriesSealSize,
                numberColor: overlayCopy,
                sealStroke: hudStepStroke(active: true)
            )
            .fixedSize(horizontal: true, vertical: true)
            .frame(maxWidth: seriesMaxWidth, alignment: .leading)
            .modifier(OverlayReadable())
            Spacer(minLength: 0)
            Text(boardStatusText ?? " ")
                .font(.system(size: overlayTypeSize, weight: .regular, design: .serif))
                .foregroundStyle(overlayCopy)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .modifier(OverlayReadable())
                .opacity(boardStatusText == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: footerSlotHeight, maxHeight: footerSlotHeight, alignment: .topLeading)
    }

    private var sealReserve: some View {
        VStack(alignment: .trailing, spacing: sealBaseRowGap * sealScale) {
            sealPiles(for: .red)
            sealPiles(for: .indigo)
        }
        .frame(height: footerSlotHeight, alignment: .bottom)
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
                    color: Theme.seal(player, palette: activeSeals),
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
        return isWhite ? Theme.waxBlack : Color.white
    }

    private var boardStatusText: String? {
        if waitingForOpponent {
            return t("gc_waiting_player")
        }
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

    private var perspectiveChip: some View {
        Button {
            is3DView.toggle()
            scene.setPerspective3D(is3DView)
            HapticsService.select(enabled: settings.hapticsEnabled)
        } label: {
            Image(systemName: is3DView ? "cube" : "square")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(hudChromeInk)
                .frame(width: meterChromeWidth, height: meterChromeHeight)
                .background(hudChromeFill, in: Capsule())
                .overlay {
                    Capsule().stroke(hudChromeInk.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: textHalo, radius: 8)
                .contentTransition(.symbolEffect(.replace, options: .speed(0.4 / 0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(is3DView ? t("view_3d") : t("view_2d"))
    }

    private var lookToggle: some View {
        Button {
            sakuraLook.cycle()
            applyBoardLook()
            scene.syncBoard(game.model, winningLine: nil, force: true)
            HapticsService.select(enabled: settings.hapticsEnabled)
        } label: {
            Circle()
                .fill(
                    LinearGradient(
                        stops: sakuraLook == .mono
                            ? [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.16),
                                .init(color: .white, location: 0.84),
                                .init(color: .white, location: 1)
                            ]
                            : [
                                .init(color: Theme.waxCinnabar, location: 0),
                                .init(color: Theme.waxDusk, location: 1)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: hudChromeHeight, height: hudChromeHeight)
                .overlay {
                    Circle().stroke(
                        sakuraLook == .color ? hudChromeFill : hudChromeInk.opacity(0.35),
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("look_settings"))
        .accessibilityValue(t(sakuraLook == .mono ? "sakura_look_mono" : "sakura_look_color"))
    }

    private var activeSeals: SealPalette { sakuraLook == .mono ? .mono : .classic }
    private var ink: Color { Color(white: 0.96) }
    private var boardInk: Color { ink }
    private var textHalo: Color { Color.black.opacity(0.55) }
    private var overlayHalo: Color { Color.black.opacity(0.55) }
    private var overlayCopy: Color { Theme.ink(dark: true) }
    private var hudChromeFill: Color {
        sakuraLook == .color ? Theme.cream : Theme.waxBlack
    }
    private var hudChromeInk: Color {
        sakuraLook == .color ? Theme.waxCinnabar : Theme.cream
    }
    private var bannerFont: Font { .system(size: 19, weight: .medium, design: .serif) }
    private var hudChromeWidth: CGFloat { 48 }
    private var hudChromeHeight: CGFloat { 36 }
    private var meterChromeHeight: CGFloat { 32 }
    private var meterChromeWidth: CGFloat { hudChromeWidth * meterChromeHeight / hudChromeHeight }
    private var turnTitleFont: Font { .system(size: 19.5, weight: .medium, design: .serif) }
    private var turnSealSize: CGFloat { 25 }
    private var hudMeterFont: Font { .system(size: 19.5, weight: .medium, design: .serif) }
    private func hudStepStroke(active: Bool) -> Color {
        ink.opacity(active ? 0.4 : 0.28)
    }
    private var turnTimerColor: Color {
        if turnSecondsLeft <= 5 { return Theme.waxRed }
        return sakuraLook == .color ? Theme.ink : Theme.cream
    }

    private var currentColor: Color {
        Theme.seal(game.currentPlayer, palette: activeSeals)
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

    private var turnTitle: String {
        if waitingForOpponent {
            return t("gc_waiting_player")
        }
        if game.mode == .gameCenter {
            return isLocalTurn ? t("turn_you") : t("turn_waiting")
        }
        if activeSeals == .mono {
            return game.currentPlayer == .red ? t("turn_black") : t("turn_white")
        }
        return game.currentPlayer == .red ? t("turn_red") : t("turn_indigo")
    }

    private var turnTimer: some View {
        Text("\(max(turnSecondsLeft, 1))")
            .font(hudMeterFont)
            .monospacedDigit()
            .foregroundStyle(turnTimerColor)
            .frame(width: meterChromeWidth, height: meterChromeHeight)
            .background(hudChromeFill, in: Capsule())
            .overlay {
                Capsule().stroke(hudChromeInk.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: textHalo, radius: 8)
            .opacity(isHumanTurn && turnSecondsLeft > 0 ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: turnSecondsLeft)
            .accessibilityLabel(t("turn_timer"))
            .accessibilityValue("\(turnSecondsLeft)")
            .accessibilityHidden(!(isHumanTurn && turnSecondsLeft > 0))
    }

    private var turnSteps: some View {
        HStack(spacing: 9) {
            stepChip(t("step_place"), active: game.phase == .place)
            Image(systemName: "arrow.right")
                .font(.system(size: 17, weight: .medium, design: .serif))
                .foregroundStyle(ink.opacity(0.35))
            stepChip(t("step_rotate"), active: game.phase == .rotate)
        }
        .animation(.easeInOut(duration: 0.28), value: game.phase)
    }

    private func stepChip(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .medium, design: .serif))
            .foregroundStyle(active ? onSeal : ink.opacity(0.55))
            .padding(.horizontal, 11.5)
            .frame(height: meterChromeHeight)
            .background(active ? currentColor : ink.opacity(0.16), in: Capsule())
            .overlay {
                Capsule().stroke(hudStepStroke(active: active), lineWidth: 1)
            }
    }

    private var isAIThinking: Bool {
        if case .ai = game.mode, game.currentPlayer == .indigo { return true }
        return false
    }

    private var isLocalTurn: Bool {
        gameCenter.isLocalTurn()
    }

    private var isHumanTurn: Bool {
        guard game.status == .playing else { return false }
        switch game.mode {
        case .ai:
            return game.currentPlayer == .red
        case .gameCenter:
            if gameCenter.isWaitingForOpponent() { return false }
            return gameCenter.isLocalTurn() && game.currentPlayer == gameCenter.localPlayerColor()
        }
    }

    private var waitingForOpponent: Bool {
        game.mode == .gameCenter && gameCenter.isWaitingForOpponent()
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
        scene.syncBoard(game.model, winningLine: {
            if case .won(_, let line) = game.status { return line }
            return nil
        }())
        scene.setPerspective3D(is3DView)
        refreshInteraction()
        if game.isFinished {
            if !game.series.hasHands {
                game.recordSeriesResult(you: seriesYou)
            }
            showResult = true
        } else if shouldStartAI {
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
        if game.mode == .gameCenter, gameCenter.hasActiveSession {
            let shouldSend = game.isFinished || game.phase == .place
            if shouldSend {
                Task { await gameCenter.submitTurn(model: game.model) }
            }
        }
    }

    private func applyBoardLook() {
        scene.applyLook(seals: activeSeals, tablet: sakuraTablet)
    }

    private func highlightWin() {
        if case .won(_, let line) = game.status {
            scene.syncBoard(game.model, winningLine: line)
        }
    }

    private var seriesYou: Player {
        if game.mode == .gameCenter {
            return gameCenter.localPlayerColor()
        }
        return .red
    }

    private func replay() {
        if game.mode == .gameCenter {
            Task { await gameCenter.requestRematch(currentModel: game.model) }
            return
        }
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

    private func requestLeave() {
        if game.mode == .gameCenter {
            confirmLeave = true
            return
        }
        leaveAndExit()
    }

    private func leaveAndExit() {
        if game.mode != .gameCenter {
            onExit()
            return
        }
        Task {
            await gameCenter.leave(currentModel: game.model)
            onExit()
        }
    }

    private func applyRemoteMatch() async {
        guard game.mode == .gameCenter, gameCenter.hasActiveSession else { return }
        if gameCenter.inviteWasDeclined() {
            handleInviteDeclined()
            return
        }
        if gameCenter.opponentLeft() {
            handleOpponentLeft()
            return
        }
        if gameCenter.isWaitingForOpponent() {
            stopTurnTimer()
            refreshInteraction()
            return
        }
        if gameCenter.bothWantRematch {
            let incoming = gameCenter.boardModel()
            if incoming.isFreshDeal {
                beginLocalRematch(incoming)
                return
            }
            if gameCenter.isLocalTurn() {
                await gameCenter.commitRematchIfNeeded()
            }
            return
        }
        let incoming = gameCenter.boardModel()
        if incoming.isFreshDeal, game.isFinished {
            beginLocalRematch(incoming)
            return
        }
        if incoming.cells == game.model.cells,
           incoming.currentPlayer == game.model.currentPlayer,
           incoming.phase == game.model.phase {
            refreshInteraction()
            if isHumanTurn {
                beginNextTurnClock()
            }
            if incoming.status != .playing {
                showResult = true
            }
            return
        }
        if canReplayRemote(incoming) {
            await playRemoteTurn(incoming)
            return
        }
        snapToRemote(incoming)
    }

    private func handleInviteDeclined() {
        inviteWatchTask?.cancel()
        stopTurnTimer()
        busy = false
        refreshInteraction()
        showInviteDeclined = true
    }

    private func leaveAfterDecline() {
        Task {
            await gameCenter.leave(currentModel: game.model)
            onExit()
        }
    }

    private func startInviteWatchIfNeeded() {
        let holdFreshSeat = gameCenter.activeMatch != nil
            && game.status == .playing
            && game.model.isFreshDeal
        guard waitingForOpponent || holdFreshSeat else {
            inviteWatchTask?.cancel()
            inviteWatchTask = nil
            return
        }
        guard inviteWatchTask == nil else { return }
        inviteWatchTask = Task {
            if waitingForOpponent {
                await gameCenter.pulseWaitingHeartbeat()
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                if waitingForOpponent {
                    await gameCenter.pulseWaitingHeartbeat()
                }
                await gameCenter.refreshActiveMatch()
            }
        }
    }

    private func handleOpponentLeft() {
        if game.status == .playing {
            game.recordForfeitWin()
        }
        stopTurnTimer()
        busy = false
        showResult = true
    }

    private func beginLocalRematch(_ incoming: BoardModel) {
        resultTask?.cancel()
        showResult = false
        selectedQuadrant = nil
        busy = false
        game.replace(with: incoming)
        scene.abandonTabletDrag()
        scene.resetTabletOrientation()
        scene.syncBoard(game.model, winningLine: nil)
        refreshInteraction()
        beginNextTurnClock()
    }

    private func canReplayRemote(_ incoming: BoardModel) -> Bool {
        guard game.phase == .place, game.status == .playing else { return false }
        guard let placement = incoming.lastPlacement else { return false }
        guard game.model.cell(at: placement) == .empty else { return false }
        if incoming.lastRotation != nil { return true }
        return incoming.status != .playing
    }

    private func playRemoteTurn(_ incoming: BoardModel) async {
        guard let placement = incoming.lastPlacement else {
            snapToRemote(incoming)
            return
        }
        scene.abandonTabletDrag()
        busy = true
        scene.setInteraction(canPlace: false, canSelectQuadrant: false)
        stopTurnTimer()
        try? await Task.sleep(for: .milliseconds(380))
        if Task.isCancelled {
            snapToRemote(incoming)
            return
        }
        let placer = game.currentPlayer
        _ = game.place(at: placement)
        scene.dropSeal(at: placement, player: placer)
        HapticsService.place(enabled: settings.hapticsEnabled)
        SoundService.place(enabled: settings.soundEnabled)
        if game.isFinished {
            busy = false
            return
        }
        guard let rotation = incoming.lastRotation else {
            snapToRemote(incoming)
            return
        }
        try? await Task.sleep(for: .milliseconds(420))
        if Task.isCancelled {
            snapToRemote(incoming)
            return
        }
        var preview = game.model
        _ = preview.rotate(quadrant: rotation.quadrant, clockwise: rotation.clockwise)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            scene.animateRotation(quadrant: rotation.quadrant, clockwise: rotation.clockwise, model: preview) {
                _ = game.rotate(quadrant: rotation.quadrant, clockwise: rotation.clockwise)
                continuation.resume()
            }
        }
        HapticsService.rotate(enabled: settings.hapticsEnabled)
        SoundService.rotate(enabled: settings.soundEnabled)
        if game.model.cells != incoming.cells {
            snapToRemote(incoming)
            return
        }
        busy = false
        refreshInteraction()
        beginNextTurnClock()
    }

    private func snapToRemote(_ incoming: BoardModel) {
        game.replace(with: incoming)
        scene.syncBoard(game.model, winningLine: {
            if case .won(_, let line) = game.status { return line }
            return nil
        }())
        busy = false
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
        guard game.status == .playing, isHumanTurn else { return }
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
                if busy { continue }
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
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.95), radius: 0, y: 1)
            .shadow(color: .black.opacity(0.8), radius: 3)
            .shadow(color: .black.opacity(0.45), radius: 8)
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
