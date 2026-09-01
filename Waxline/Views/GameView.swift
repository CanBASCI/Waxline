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
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.ink.opacity(0.55), lineWidth: 2)
                            .allowsHitTesting(false)
                        perspectiveButton
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            footer
        }
        .background(Theme.cream.ignoresSafeArea())
        .onAppear { configureScene() }
        .onChange(of: game.status) { _, newStatus in
            if newStatus != .playing {
                highlightWin()
                showResult = true
                HapticsService.win(enabled: settings.hapticsEnabled)
                SoundService.win(enabled: settings.soundEnabled)
            }
        }
        .onChange(of: gameCenter.matchRevision) { _, _ in
            reloadRemoteMatch()
        }
        .sheet(isPresented: $showResult) {
            ResultSheet(game: game, onAgain: replay, onMenu: onExit)
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        HStack {
            Button(t("menu")) { onExit() }
                .font(.system(.body, design: .serif).weight(.medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            VStack(spacing: 4) {
                Text(turnTitle)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(currentColor)
                Text(phaseTitle)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.65))
            }
            Spacer()
            Circle()
                .fill(currentColor)
                .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if game.phase == .rotate, canAct, !busy {
                Text(t("rotate_hint"))
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                HStack(spacing: 20) {
                    rotateButton(t("rotate_ccw"), clockwise: false)
                    rotateButton(t("rotate_cw"), clockwise: true)
                }
                .opacity(selectedQuadrant == nil ? 0.35 : 1)
                .disabled(selectedQuadrant == nil)
            } else if busy, isAIThinking {
                Text(t("waiting_ai"))
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.7))
            } else if game.mode == .gameCenter, !isLocalTurn {
                Text(t("turn_waiting"))
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.7))
            }
        }
        .frame(minHeight: 92)
        .padding(.bottom, 18)
    }

    private var perspectiveButton: some View {
        Button {
            is3DView.toggle()
            scene.setPerspective3D(is3DView)
            HapticsService.select(enabled: settings.hapticsEnabled)
        } label: {
            Text(is3DView ? t("view_3d") : t("view_2d"))
                .font(.system(.subheadline, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.cream.opacity(0.94), in: Capsule())
                .overlay {
                    Capsule().stroke(Theme.ink.opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel(is3DView ? t("view_3d") : t("view_2d"))
    }

    private func rotateButton(_ title: String, clockwise: Bool) -> some View {
        Button {
            applyRotation(clockwise: clockwise)
        } label: {
            Label(title, systemImage: clockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(Theme.cream)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var currentColor: Color {
        game.currentPlayer == .red ? Theme.waxRed : Theme.waxIndigo
    }

    private var turnTitle: String {
        if game.mode == .gameCenter {
            return isLocalTurn ? t("turn_you") : t("turn_waiting")
        }
        return game.currentPlayer == .red ? t("turn_red") : t("turn_indigo")
    }

    private var phaseTitle: String {
        if game.status != .playing { return "" }
        return game.phase == .place ? t("phase_place") : t("phase_rotate")
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
            guard canAct, game.phase == .rotate else { return }
            selectedQuadrant = quadrant
            HapticsService.select(enabled: settings.hapticsEnabled)
        }
        scene.onRotateGesture = { clockwise in
            applyRotation(clockwise: clockwise)
        }
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
        guard canAct, let quadrant = selectedQuadrant else { return }
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
