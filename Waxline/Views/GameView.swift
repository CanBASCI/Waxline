import SwiftUI

struct GameView: View {
    @Bindable var game: GameState
    var onExit: () -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter
    @State private var scene = BoardSceneController()
    @State private var selectedQuadrant: Quadrant?
    @State private var busy = false
    @State private var showResult = false
    @State private var is3DView = true
    @State private var showLookPanel = false
    @State private var resultTask: Task<Void, Never>?

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            BoardSceneView(controller: scene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(ink.opacity(0.55), lineWidth: 2)
                        .allowsHitTesting(false)
                }
                .overlay {
                    if showLookPanel {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { showLookPanel = false }
                    }
                }
                .overlay(alignment: .topLeading) {
                    lookMenu
                        .padding(10)
                }
                .overlay(alignment: .topTrailing) {
                    perspectiveChip
                        .padding(10)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            footer
        }
        .background(canvas.ignoresSafeArea())
        .preferredColorScheme(isDark ? .dark : .light)
        .onAppear { configureScene() }
        .onChange(of: game.status) { _, newStatus in
            if newStatus != .playing {
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
            ResultSheet(game: game, onAgain: replay, onMenu: onExit)
                .presentationDetents([.height(240)])
        }
        .onDisappear { resultTask?.cancel() }
    }

    private var header: some View {
        HStack {
            Button(t("menu")) { onExit() }
                .font(.system(.body, design: .serif).weight(.medium))
                .foregroundStyle(ink)
            Spacer()
            VStack(spacing: 6) {
                Text(turnTitle)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(titleColor)
                if game.status == .playing {
                    turnSteps
                }
            }
            Spacer()
            Circle()
                .fill(currentColor)
                .overlay {
                    Circle().stroke(ink.opacity(0.4), lineWidth: settings.sealPalette == .mono ? 1 : 0)
                }
                .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if showLookPanel { showLookPanel = false }
                }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if game.phase == .rotate, canAct, !busy {
                Text(t("rotate_hint"))
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(ink.opacity(0.7))
                HStack(spacing: 20) {
                    rotateButton(t("rotate_ccw"), clockwise: false)
                    rotateButton(t("rotate_cw"), clockwise: true)
                }
                .opacity(selectedQuadrant == nil ? 0.35 : 1)
                .disabled(selectedQuadrant == nil)
            } else if busy, isAIThinking {
                Text(t(settings.sealPalette == .mono ? "waiting_white" : "waiting_ai"))
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(ink.opacity(0.7))
            } else if game.mode == .gameCenter, !isLocalTurn {
                Text(t("turn_waiting"))
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(ink.opacity(0.7))
            }
        }
        .frame(minHeight: 92)
        .padding(.bottom, 18)
        .contentShape(Rectangle())
        .onTapGesture {
            if showLookPanel { showLookPanel = false }
        }
    }

    private var perspectiveChip: some View {
        lookChip(is3DView ? t("view_3d") : t("view_2d")) {
            is3DView.toggle()
            scene.setPerspective3D(is3DView)
        }
        .accessibilityLabel(is3DView ? t("view_3d") : t("view_2d"))
    }

    private var lookMenu: some View {
        HStack(alignment: .center, spacing: 6) {
            Button {
                showLookPanel.toggle()
                HapticsService.select(enabled: settings.hapticsEnabled)
            } label: {
                Image(systemName: showLookPanel ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 32, height: 32)
                    .background(Theme.chipFill(dark: isDark), in: Circle())
                    .overlay {
                        Circle().stroke(ink.opacity(0.35), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("look_settings"))

            if showLookPanel {
                HStack(spacing: 6) {
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
                        applyBoardLook()
                    }
                    lookChip(t(tableTitleKey)) {
                        settings.tableFinish.cycle()
                        applyBoardLook()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showLookPanel)
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
                .background(Theme.chipFill(dark: isDark), in: Capsule())
                .overlay {
                    Capsule().stroke(ink.opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func rotateButton(_ title: String, clockwise: Bool) -> some View {
        Button {
            applyRotation(clockwise: clockwise)
        } label: {
            Label(title, systemImage: clockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(canvas)
                .background(ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var isDark: Bool { settings.boardDark }
    private var canvas: Color { Theme.canvas(dark: isDark) }
    private var ink: Color { Theme.ink(dark: isDark) }

    private var currentColor: Color {
        Theme.seal(game.currentPlayer, palette: settings.sealPalette)
    }

    private var titleColor: Color {
        if !isDark, settings.sealPalette == .mono, game.currentPlayer == .indigo {
            return ink
        }
        return currentColor
    }

    private var onSeal: Color {
        if settings.sealPalette == .mono, game.currentPlayer == .indigo {
            return Theme.ink
        }
        return Theme.cream
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

    private var turnSteps: some View {
        HStack(spacing: 8) {
            stepChip(t("step_place"), active: game.phase == .place)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(ink.opacity(0.35))
            stepChip(t("step_rotate"), active: game.phase == .rotate)
        }
        .animation(.easeInOut(duration: 0.28), value: game.phase)
    }

    private func stepChip(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(.caption, design: .serif).weight(.semibold))
            .foregroundStyle(active ? onSeal : ink.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(active ? currentColor : ink.opacity(isDark ? 0.16 : 0.08), in: Capsule())
    }

    private var isAIThinking: Bool {
        if case .ai = game.mode, game.currentPlayer == .indigo { return true }
        return false
    }

    private var isLocalTurn: Bool {
        guard let match = gameCenter.activeMatch else { return true }
        return gameCenter.isLocalTurn(match)
    }

    private var canAct: Bool {
        guard game.status == .playing, !busy else { return false }
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
        refreshInteraction()
        if shouldStartAI {
            Task { await playAI() }
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

    private func applyRotation(clockwise: Bool) {
        guard let quadrant = selectedQuadrant else { return }
        applyRotation(quadrant: quadrant, clockwise: clockwise)
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
                Task { await playAI() }
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

    private func applyBoardLook() {
        scene.applyLook(
            dark: settings.boardDark,
            seals: settings.sealPalette,
            table: settings.tableFinish,
            tablet: settings.tabletFinish
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
        scene.syncBoard(game.model, winningLine: nil)
        refreshInteraction()
    }

    private func reloadRemoteMatch() {
        guard game.mode == .gameCenter, let match = gameCenter.activeMatch else { return }
        game.replace(with: gameCenter.model(from: match))
        scene.syncBoard(game.model, winningLine: {
            if case .won(_, let line) = game.status { return line }
            return nil
        }())
        refreshInteraction()
    }

    private func playAI() async {
        guard case .ai(let level) = game.mode, game.currentPlayer == .indigo, game.status == .playing else { return }
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
    }
}
