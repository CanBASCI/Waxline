@preconcurrency import SceneKit
import simd
import UIKit

@MainActor
final class BoardSceneController: NSObject {
    let scene = SCNScene()
    weak var scnView: SCNView?

    var onCellTap: ((Position) -> Void)?
    var onQuadrantTap: ((Quadrant?) -> Void)?
    var onRotateGesture: ((Quadrant, Bool) -> Void)?

    private let boardRoot = SCNNode()
    private var tableNode = SCNNode()
    private var sealPalette: SealPalette = .classic
    private var boardSkin: GameSkin = .classic
    private var ambientLightNode = SCNNode()
    private var sunLightNode = SCNNode()
    private var fillLightNode = SCNNode()
    private var quadrantNodes: [Quadrant: SCNNode] = [:]
    private var cellNodes: [String: SCNNode] = [:]
    private var sealNodes: [String: SCNNode] = [:]
    private var sealTemplates: [String: SCNNode] = [:]

    private var allowsCellTaps = true
    private var allowsQuadrantTaps = false
    private var selectedQuadrant: Quadrant?
    private var isAnimating = false
    private var rotationCompletion: (() -> Void)?
    private var cameraNode = SCNNode()
    private var panStartAngle: Float = 0
    private var restYaw: Float = 0
    private var cameraTilt: Float = 0
    private var panStartTabletYaw: Float = 0
    private var panTabletCenter = SIMD2<Float>.zero
    private var panTabletDelta: Float = 0
    private var panLastFingerAngle: Float = 0
    private var panUnwrappedDelta: Float = 0
    private var panQuadrant: Quadrant?
    private var panRotatingTablet = false
    private var panSpinningTable = false
    private var lastViewSize = CGSize(width: 390, height: 520)

    private let playScale: Float = 1.10
    private let cellSize: Float = 0.92 * 1.10
    private let gap: Float = 0.30
    private let tableSize: Float = 7.24
    private let viewFitHalf: Float = 3.6
    private let tabletThick: Float = 0.68
    private let tableSpinScale: Float = 0.86
    private let boardScreenLift: Float = 0.60
    private var boardRestPosition: SCNVector3 { SCNVector3(0, 0, -boardScreenLift) }
    private var sheetPad: Float { 0.08 * playScale }
    private var slab: Float { playScale * tabletThick }
    private var boardPlayHalf: Float {
        let span = cellSize * 1.5 + gap / 2
        let tabletHalf = (cellSize * 3 + sheetPad) / 2
        return span + tabletHalf
    }

    override init() {
        super.init()
        buildScene()
    }

    func setInteraction(canPlace: Bool, canSelectQuadrant: Bool) {
        if !canSelectQuadrant {
            abandonTabletDrag()
        }
        allowsCellTaps = canPlace && !isAnimating
        allowsQuadrantTaps = canSelectQuadrant && !isAnimating
        stopRotateInvite()
        poseTablets(canSelect: canSelectQuadrant)
        if canSelectQuadrant, selectedQuadrant == nil {
            startRotateInvite()
        }
    }

    func abandonTabletDrag() {
        let wasSpinningTable = panSpinningTable
        let wasHoldingTablet = panRotatingTablet || selectedQuadrant != nil
        panRotatingTablet = false
        panSpinningTable = false
        panQuadrant = nil
        panTabletDelta = 0
        panUnwrappedDelta = 0
        selectedQuadrant = nil
        onQuadrantTap?(nil)
        guard wasHoldingTablet || wasSpinningTable else { return }
        if !isAnimating {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.22
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for node in quadrantNodes.values {
                node.eulerAngles.y = 0
            }
            SCNTransaction.commit()
            poseTablets(canSelect: false)
        }
        if wasSpinningTable {
            snapBoard(to: restYaw)
        }
    }

    private func stopRotateInvite() {
        for node in quadrantNodes.values {
            node.removeAction(forKey: "inviteRotate")
        }
    }

    private func poseTablets(canSelect: Bool) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.28
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let shrinkIdle = boardSkin == .sakura && canSelect && selectedQuadrant != nil
        for (quadrant, node) in quadrantNodes {
            let selected = selectedQuadrant == quadrant && canSelect
            if selected {
                node.position = boardSkin == .sakura ? restPosition(for: quadrant) : selectedPosition(for: quadrant)
                let grow: Float = boardSkin == .sakura ? 1 : 1.045
                node.scale = SCNVector3(grow, grow, grow)
            } else {
                node.position = restPosition(for: quadrant)
                let shrink: Float = shrinkIdle ? 0.88 : 1
                node.scale = SCNVector3(shrink, shrink, shrink)
            }
        }
        SCNTransaction.commit()
    }

    private func startRotateInvite() {
        for (quadrant, node) in quadrantNodes {
            let rest = restPosition(for: quadrant)
            let delay = SCNAction.wait(duration: 0.08 * Double(quadrant.rawValue))
            let up = SCNAction.move(to: SCNVector3(rest.x, 0.34, rest.z), duration: 0.52)
            up.timingMode = .easeInEaseOut
            let down = SCNAction.move(to: SCNVector3(rest.x, rest.y, rest.z), duration: 0.52)
            down.timingMode = .easeInEaseOut
            let twoLifts = SCNAction.sequence([up, down, up, down])
            let wait = SCNAction.wait(duration: 5)
            let loop = SCNAction.repeatForever(.sequence([twoLifts, wait]))
            node.runAction(.sequence([delay, loop]), forKey: "inviteRotate")
        }
    }

    private func restPosition(for quadrant: Quadrant) -> SCNVector3 {
        var position = quadrantCenter(quadrant)
        position.y = 0.16
        return position
    }

    private func selectedPosition(for quadrant: Quadrant) -> SCNVector3 {
        var position = quadrantCenter(quadrant)
        let nudge: Float = 0.055 * playScale
        position.x += position.x >= 0 ? nudge : -nudge
        position.z += position.z >= 0 ? nudge : -nudge
        position.y = 0.58
        return position
    }

    func syncBoard(_ model: BoardModel, winningLine: [Position]?) {
        WaxlinePerf.measure("syncBoard") {
            clearWinHighlight()
            for row in 0..<6 {
                for col in 0..<6 {
                    let key = cellKey(row: row, col: col)
                    updateSeal(key: key, cell: model.cells[row][col], glow: false)
                }
            }
            if let winningLine {
                showWin(line: winningLine, model: model)
            }
        }
    }

    func dropSeal(at position: Position, player: Player) {
        WaxlinePerf.measure("dropSeal \(position.row),\(position.col)") {
            let key = cellKey(row: position.row, col: position.col)
            updateSeal(key: key, cell: player.cell, glow: false)
            if let node = sealNodes[key] {
                node.position.y = 0.7 * playScale
                node.runAction(.moveBy(x: 0, y: Double(-0.63 * playScale), z: 0, duration: 0.22))
            }
        }
    }

    func animateRotation(quadrant: Quadrant, clockwise: Bool, model: BoardModel, completion: @escaping () -> Void) {
        guard let node = quadrantNodes[quadrant] else {
            completion()
            return
        }
        WaxlinePerf.event("rotate.start", "\(quadrant)")
        isAnimating = true
        allowsCellTaps = false
        allowsQuadrantTaps = false
        stopRotateInvite()
        rotationCompletion = completion
        let target: Float = clockwise ? -.pi / 2 : .pi / 2
        if abs(node.eulerAngles.y - target) < 0.08 {
            finishRotation(quadrant: quadrant, model: model)
            return
        }
        if cameraTilt <= 0.35 {
            let fit = tabletSpinFitScale(quadrant: quadrant, yaw: .pi / 4)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            node.scale = SCNVector3(fit, fit, fit)
            SCNTransaction.commit()
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.38
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        SCNTransaction.completionBlock = { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishRotation(quadrant: quadrant, model: model)
            }
        }
        node.eulerAngles.y = target
        SCNTransaction.commit()
    }

    private func finishRotation(quadrant: Quadrant, model: BoardModel) {
        WaxlinePerf.event("rotate.finish", "\(quadrant)")
        if let node = quadrantNodes[quadrant] {
            node.eulerAngles.y = 0
            node.scale = SCNVector3(1, 1, 1)
        }
        syncBoard(model, winningLine: nil)
        selectedQuadrant = nil
        isAnimating = false
        let done = rotationCompletion
        rotationCompletion = nil
        done?()
    }

    func applyLook(
        dark: Bool,
        seals: SealPalette,
        table: TableFinish,
        tablet: TabletFinish,
        clearCanvas: Bool = false,
        skin: GameSkin = .classic,
        sakuraTable: SakuraTableTheme = .oak,
        sakuraTablet: SakuraTabletTheme = .grey,
        showTable: Bool = true
    ) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let previousSkin = boardSkin
        let previousPalette = sealPalette
        sealPalette = seals
        boardSkin = skin
        if clearCanvas {
            scene.background.contents = UIColor.clear
            scnView?.backgroundColor = .clear
            scnView?.isOpaque = false
            scnView?.layer.isOpaque = false
        } else {
            scene.background.contents = dark ? PaperStyle.darkCanvas : PaperStyle.cream
            scnView?.backgroundColor = dark ? PaperStyle.darkCanvas : PaperStyle.cream
            scnView?.isOpaque = true
            scnView?.layer.isOpaque = true
        }
        applyLighting(skin: skin, dark: dark)
        if skin == .sakura {
            scene.lightingEnvironment.contents = PaperStyle.sakuraLightingCube()
            scene.lightingEnvironment.intensity = dark ? 0.38 : 0.52
        } else {
            scene.lightingEnvironment.contents = PaperStyle.waxLightingCube()
            scene.lightingEnvironment.intensity = 0.45
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        let wood = PaperStyle.tableMaterial(table, skin: skin, sakuraTable: sakuraTable)
        tableNode.geometry?.materials = [wood, wood, wood, wood, wood, wood]
        tableNode.isHidden = !showTable
        for (quadrant, node) in quadrantNodes {
            let top = PaperStyle.tabletMaterial(tablet, recessed: false, offset: Float(quadrant.rawValue) * 0.17, skin: skin, sakuraTablet: sakuraTablet)
            let edge = PaperStyle.tabletMaterial(tablet, recessed: true, offset: Float(quadrant.rawValue) * 0.11, skin: skin, sakuraTablet: sakuraTablet)
            paintTablet(node, top: top, edge: edge, glass: skin == .sakura && sakuraTablet == .glass)
        }
        SCNTransaction.commit()
        scnView?.antialiasingMode = clearCanvas ? .none : .multisampling4X
        setTabletShadowsVisible(!(skin == .sakura && sakuraTablet == .glass))
        if previousSkin != skin || previousPalette != seals {
            warmSealTemplates()
        }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        WaxlinePerf.event(
            "applyLook.done",
            String(format: "%.1fms skin=\(skin) table=\(showTable) msaa=\(clearCanvas ? "none" : "4x")", ms)
        )
    }

    func applySurfaces(
        table: TableFinish,
        tablet: TabletFinish,
        skin: GameSkin = .classic,
        sakuraTable: SakuraTableTheme = .oak,
        sakuraTablet: SakuraTabletTheme = .grey,
        showTable: Bool = true
    ) {
        let t0 = CFAbsoluteTimeGetCurrent()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        let wood = PaperStyle.tableMaterial(table, skin: skin, sakuraTable: sakuraTable)
        tableNode.geometry?.materials = [wood, wood, wood, wood, wood, wood]
        tableNode.isHidden = !showTable
        for (quadrant, node) in quadrantNodes {
            let top = PaperStyle.tabletMaterial(tablet, recessed: false, offset: Float(quadrant.rawValue) * 0.17, skin: skin, sakuraTablet: sakuraTablet)
            let edge = PaperStyle.tabletMaterial(tablet, recessed: true, offset: Float(quadrant.rawValue) * 0.11, skin: skin, sakuraTablet: sakuraTablet)
            paintTablet(node, top: top, edge: edge, glass: skin == .sakura && sakuraTablet == .glass)
        }
        setTabletShadowsVisible(!(skin == .sakura && sakuraTablet == .glass))
        SCNTransaction.commit()
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        WaxlinePerf.event("applyLook.surfaces", String(format: "%.1fms", ms))
    }

    func setTableVisible(_ visible: Bool) {
        tableNode.isHidden = !visible
        WaxlinePerf.event("table.visible", "\(visible)")
    }

    private func warmSealTemplates() {
        for player in Player.allCases {
            let color = PaperStyle.waxColor(for: player, palette: sealPalette, skin: boardSkin)
            let motif = (sealPalette == .mono && player == .indigo) ? PaperStyle.waxBlack : UIColor(red: 0.95, green: 0.82, blue: 0.45, alpha: 1)
            let probeName = "seal_gpu_warm_\(player.rawValue)"
            _ = clonedSeal(color: color, motifColor: motif, glow: false)
            if boardRoot.childNode(withName: probeName, recursively: false) == nil {
                let probe = clonedSeal(color: color, motifColor: motif, glow: false)
                probe.name = probeName
                probe.isHidden = true
                probe.position = SCNVector3(0, -8, 0)
                boardRoot.addChildNode(probe)
            }
        }
    }

    private func applyLighting(skin: GameSkin, dark: Bool = false) {
        if skin == .sakura, dark {
            ambientLightNode.light?.color = UIColor(red: 0.62, green: 0.60, blue: 0.66, alpha: 1)
            ambientLightNode.light?.intensity = 320
            sunLightNode.light?.color = UIColor(red: 0.82, green: 0.80, blue: 0.86, alpha: 1)
            sunLightNode.light?.intensity = 420
            fillLightNode.light?.color = UIColor(red: 0.55, green: 0.50, blue: 0.62, alpha: 1)
            fillLightNode.light?.intensity = 180
            sunLightNode.light?.castsShadow = false
        } else if skin == .sakura {
            ambientLightNode.light?.color = UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1)
            ambientLightNode.light?.intensity = 460
            sunLightNode.light?.color = UIColor(red: 1.00, green: 0.99, blue: 0.97, alpha: 1)
            sunLightNode.light?.intensity = 580
            fillLightNode.light?.color = UIColor(red: 0.86, green: 0.88, blue: 0.94, alpha: 1)
            fillLightNode.light?.intensity = 220
            sunLightNode.light?.castsShadow = false
        } else {
            ambientLightNode.light?.color = UIColor(white: 0.48, alpha: 1)
            ambientLightNode.light?.intensity = 380
            sunLightNode.light?.color = UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
            sunLightNode.light?.intensity = 720
            fillLightNode.light?.color = UIColor(red: 0.95, green: 0.9, blue: 1, alpha: 1)
            fillLightNode.light?.intensity = 260
            sunLightNode.light?.castsShadow = true
        }
    }

    private func setTabletShadowsVisible(_ visible: Bool) {
        for node in quadrantNodes.values {
            node.childNode(withName: "quad_shadow", recursively: false)?.isHidden = !visible
        }
    }

    private func paintTablet(_ node: SCNNode, top: SCNMaterial, edge: SCNMaterial, glass: Bool = false) {
        let name = node.name ?? ""
        if name.hasSuffix("_floor") {
            node.isHidden = glass
            if !glass, let box = node.geometry as? SCNBox {
                box.materials = [edge]
            }
        } else if name.hasSuffix("_wall") || name.hasSuffix("_grid"), let box = node.geometry as? SCNBox {
            node.isHidden = false
            box.materials = [edge]
        } else if name.hasPrefix("quad_"), let box = node.geometry as? SCNBox {
            if glass {
                box.materials = [top, top, top, top, top, top]
            } else {
                box.materials = [edge, edge, edge, edge, top, edge]
            }
        }
        for child in node.childNodes {
            paintTablet(child, top: top, edge: edge, glass: glass)
        }
    }

    func setPerspective3D(_ is3D: Bool) {
        cameraTilt = is3D ? 1 : 0
        applyCamera(animated: true)
    }

    func beginPan() {
        boardRoot.position = boardRestPosition
        panStartAngle = restYaw
        panStartTabletYaw = 0
        panTabletDelta = 0
    }

    func beginTablePan(at viewPoint: CGPoint, in view: SCNView) {
        WaxlinePerf.event("table.spin.start", "hidden=\(tableNode.isHidden)")
        boardRoot.position = boardRestPosition
        panStartAngle = restYaw
        panTabletDelta = 0
        panUnwrappedDelta = 0
        let origin = boardRoot.convertPosition(SCNVector3Zero, to: nil)
        let center = SIMD2(origin.x, origin.z)
        panTabletCenter = center
        let point = worldXZ(from: viewPoint, in: view) ?? center
        panLastFingerAngle = fingerAngle(at: point, center: center)
        applyTableSpinPose(animated: cameraTilt > 0.35)
    }

    func updateTablePan(at viewPoint: CGPoint, in view: SCNView) {
        guard !isAnimating else { return }
        guard let now = worldXZ(from: viewPoint, in: view) else { return }
        let vector = now - panTabletCenter
        if simd_length(vector) > 0.08 {
            let angle = fingerAngle(at: now, center: panTabletCenter)
            panUnwrappedDelta += wrappedDelta(from: panLastFingerAngle, to: angle)
            panLastFingerAngle = angle
            let limit = Float.pi / 2
            panTabletDelta = min(max(panUnwrappedDelta, -limit), limit)
        }
        applyTableSpinPose(animated: false)
    }

    private func applyTableSpinPose(animated: Bool) {
        let yaw = panStartAngle + panTabletDelta
        let fit = cameraTilt > 0.35 ? tableSpinScale : tableSpinFitScale(for: yaw)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.22 : 0
        if animated {
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        } else {
            SCNTransaction.disableActions = true
        }
        boardRoot.position = boardRestPosition
        boardRoot.eulerAngles.y = yaw
        boardRoot.scale = SCNVector3(fit, fit, fit)
        SCNTransaction.commit()
    }

    private func tableSpinFitScale(for yaw: Float) -> Float {
        let limit = viewFitHalf * 0.80
        let span = cellSize * 1.5 + gap / 2
        let half = (cellSize * 3 + sheetPad) / 2
        let cosine = cos(yaw)
        let sine = sin(yaw)
        var reach: Float = 0
        for sx: Float in [-1, 1] {
            for sz: Float in [-1, 1] {
                let cx = sx * span
                let cz = sz * span
                for lx in [-half, half] {
                    for lz in [-half, half] {
                        let x = cx + lx
                        let z = cz + lz
                        let wx = x * cosine - z * sine
                        let wz = x * sine + z * cosine
                        reach = max(reach, abs(wx), abs(wz))
                    }
                }
            }
        }
        return min(1, limit / max(reach, 0.1))
    }

    private func tabletSpinFitScale(quadrant: Quadrant, yaw: Float) -> Float {
        let origin = boardSkin == .sakura ? restPosition(for: quadrant) : selectedPosition(for: quadrant)
        let half = (cellSize * 3 + sheetPad) / 2
        let limit = viewFitHalf * 0.94
        let cosine = cos(yaw)
        let sine = sin(yaw)
        var fit: Float = 1
        for lx in [-half, half] {
            for lz in [-half, half] {
                let dx = lx * cosine - lz * sine
                let dz = lx * sine + lz * cosine
                if dx > 0.0001 { fit = min(fit, (limit - origin.x) / dx) }
                if dx < -0.0001 { fit = min(fit, (-limit - origin.x) / dx) }
                if dz > 0.0001 { fit = min(fit, (limit - origin.z) / dz) }
                if dz < -0.0001 { fit = min(fit, (-limit - origin.z) / dz) }
            }
        }
        return min(1, max(0.88, fit))
    }

    func endTablePan() {
        WaxlinePerf.event("table.spin.end", String(format: "delta=%.2f hidden=%@", panTabletDelta, String(describing: tableNode.isHidden)))
        guard !isAnimating else {
            snapBoard(to: restYaw)
            return
        }
        let quarter = Float.pi / 2
        if abs(panTabletDelta) > 0.28 {
            restYaw += panTabletDelta > 0 ? quarter : -quarter
        }
        snapBoard(to: restYaw)
    }

    private func beginTabletPan(at viewPoint: CGPoint, in view: SCNView) {
        WaxlinePerf.event("tablet.spin.start", "\(panQuadrant?.rawValue ?? -1)")
        guard let quadrant = panQuadrant, let node = quadrantNodes[quadrant] else { return }
        selectTablet(quadrant)
        panStartTabletYaw = node.eulerAngles.y
        panTabletDelta = 0
        panUnwrappedDelta = 0
        let pivot = boardSkin == .sakura ? restPosition(for: quadrant) : selectedPosition(for: quadrant)
        let center = SIMD2(pivot.x, pivot.z)
        panTabletCenter = center
        let point = boardXZ(from: viewPoint, in: view) ?? center
        panLastFingerAngle = fingerAngle(at: point, center: center)
    }

    private func updateTabletPan(at viewPoint: CGPoint, in view: SCNView) {
        guard !isAnimating, allowsQuadrantTaps, let quadrant = panQuadrant, let node = quadrantNodes[quadrant] else { return }
        guard let now = boardXZ(from: viewPoint, in: view) else { return }
        let vector = now - panTabletCenter
        guard simd_length(vector) > 0.12 else { return }
        let angle = fingerAngle(at: now, center: panTabletCenter)
        panUnwrappedDelta += wrappedDelta(from: panLastFingerAngle, to: angle)
        panLastFingerAngle = angle
        let limit = Float.pi / 2
        panTabletDelta = min(max(panUnwrappedDelta, -limit), limit)
        let yaw = panStartTabletYaw + panTabletDelta
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        node.eulerAngles.y = yaw
        if cameraTilt <= 0.35 {
            let fit = tabletSpinFitScale(quadrant: quadrant, yaw: yaw)
            node.scale = SCNVector3(fit, fit, fit)
        }
        SCNTransaction.commit()
    }

    private func endTabletPan() {
        WaxlinePerf.event("tablet.spin.end", String(format: "delta=%.2f", panTabletDelta))
        guard allowsQuadrantTaps, !isAnimating else { return }
        if abs(panTabletDelta) > 0.28, let quadrant = panQuadrant {
            onRotateGesture?(quadrant, panTabletDelta < 0)
            return
        }
        if let quadrant = panQuadrant, let node = quadrantNodes[quadrant] {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.28
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            node.eulerAngles.y = 0
            if cameraTilt <= 0.35 {
                node.scale = SCNVector3(1, 1, 1)
            }
            SCNTransaction.commit()
        }
        clearTabletSelection()
    }

    private func worldXZ(from viewPoint: CGPoint, in view: SCNView) -> SIMD2<Float>? {
        guard let world = boardPoint(from: viewPoint, in: view) else { return nil }
        return SIMD2(world.x, world.z)
    }

    private func boardXZ(from viewPoint: CGPoint, in view: SCNView) -> SIMD2<Float>? {
        guard let world = boardPoint(from: viewPoint, in: view) else { return nil }
        let local = boardRoot.convertPosition(world, from: nil)
        return SIMD2(local.x, local.z)
    }

    private func fingerAngle(at point: SIMD2<Float>, center: SIMD2<Float>) -> Float {
        let vector = point - center
        return atan2(vector.x, vector.y)
    }

    private func wrappedDelta(from previous: Float, to next: Float) -> Float {
        var step = next - previous
        let pi = Float.pi
        if step > pi { step -= 2 * pi }
        if step < -pi { step += 2 * pi }
        return step
    }

    @objc func handleBoardPan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view as? SCNView else { return }
        let location = gesture.location(in: view)
        switch gesture.state {
        case .began:
            beginPan()
            panRotatingTablet = false
            panSpinningTable = false
            panQuadrant = nil
            if allowsQuadrantTaps, let world = boardPoint(from: location, in: view), let quadrant = quadrant(at: world) {
                panQuadrant = quadrant
                panRotatingTablet = true
                beginTabletPan(at: location, in: view)
            } else if let world = boardPoint(from: location, in: view), isOnTable(world) {
                break
            } else {
                panSpinningTable = true
                beginTablePan(at: location, in: view)
            }
        case .changed:
            if panRotatingTablet {
                updateTabletPan(at: location, in: view)
            } else if panSpinningTable {
                updateTablePan(at: location, in: view)
            }
        case .ended, .cancelled, .failed:
            if panRotatingTablet {
                endTabletPan()
            } else if panSpinningTable {
                endTablePan()
            }
            panRotatingTablet = false
            panSpinningTable = false
            panQuadrant = nil
        default:
            break
        }
    }

    private func snapBoard(to yaw: Float) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.38
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        boardRoot.position = boardRestPosition
        boardRoot.eulerAngles.y = yaw
        boardRoot.scale = SCNVector3(1, 1, 1)
        SCNTransaction.commit()
    }

    func handleTouchBegan(at viewPoint: CGPoint, in view: SCNView) {
        guard !isAnimating, allowsQuadrantTaps else { return }
        guard let world = boardPoint(from: viewPoint, in: view), let quadrant = quadrant(at: world) else { return }
        selectTablet(quadrant)
    }

    func handleTouchEnded() {
        guard !isAnimating, !panRotatingTablet else { return }
        clearTabletSelection()
    }

    private func selectTablet(_ quadrant: Quadrant) {
        if selectedQuadrant == quadrant {
            stopRotateInvite()
            return
        }
        selectedQuadrant = quadrant
        setInteraction(canPlace: false, canSelectQuadrant: true)
        onQuadrantTap?(quadrant)
    }

    private func clearTabletSelection() {
        guard selectedQuadrant != nil else { return }
        selectedQuadrant = nil
        onQuadrantTap?(nil)
        setInteraction(canPlace: false, canSelectQuadrant: allowsQuadrantTaps)
    }

    func handleTap(at viewPoint: CGPoint, in view: SCNView) {
        guard !isAnimating else { return }
        guard let world = boardPoint(from: viewPoint, in: view) else { return }
        if allowsCellTaps, let position = cell(at: world) {
            onCellTap?(position)
        }
    }

    private func boardPoint(from viewPoint: CGPoint, in view: SCNView) -> SCNVector3? {
        let near = view.unprojectPoint(SCNVector3(Float(viewPoint.x), Float(viewPoint.y), 0))
        let far = view.unprojectPoint(SCNVector3(Float(viewPoint.x), Float(viewPoint.y), 1))
        let dy = far.y - near.y
        guard abs(dy) > 0.0001 else { return nil }
        let t = (0.22 - near.y) / dy
        return SCNVector3(
            near.x + (far.x - near.x) * t,
            0.22,
            near.z + (far.z - near.z) * t
        )
    }

    private func isOnTable(_ world: SCNVector3) -> Bool {
        let local = boardRoot.convertPosition(world, from: nil)
        let half = tableSize / 2
        return abs(local.x) <= half && abs(local.z) <= half
    }

    private func cell(at world: SCNVector3) -> Position? {
        let local = boardRoot.convertPosition(world, from: nil)
        for quadrant in Quadrant.allCases {
            guard let node = quadrantNodes[quadrant] else { continue }
            let lx = local.x - node.position.x
            let lz = local.z - node.position.z
            let localCol = Int((lx / cellSize + 1.5).rounded(.down))
            let localRow = Int((lz / cellSize + 1.5).rounded(.down))
            if (0..<3).contains(localCol), (0..<3).contains(localRow) {
                return Position(row: quadrant.rowOffset + localRow, col: quadrant.colOffset + localCol)
            }
        }
        return nil
    }

    private func quadrant(at world: SCNVector3) -> Quadrant? {
        let local = boardRoot.convertPosition(world, from: nil)
        let half = (cellSize * 3 + sheetPad) / 2 + 0.1
        var best: Quadrant?
        var bestDist = Float.greatestFiniteMagnitude
        for quadrant in Quadrant.allCases {
            guard let node = quadrantNodes[quadrant] else { continue }
            let dx = local.x - node.position.x
            let dz = local.z - node.position.z
            guard abs(dx) <= half, abs(dz) <= half else { continue }
            let dist = dx * dx + dz * dz
            if dist < bestDist {
                bestDist = dist
                best = quadrant
            }
        }
        return best
    }

    func selectQuadrant(_ quadrant: Quadrant?) {
        selectedQuadrant = quadrant
        setInteraction(canPlace: allowsCellTaps, canSelectQuadrant: allowsQuadrantTaps || quadrant != nil)
    }

    private func buildScene() {
        scene.background.contents = PaperStyle.cream
        scene.lightingEnvironment.contents = PaperStyle.waxLightingCube()
        scene.lightingEnvironment.intensity = 0.45
        scene.rootNode.addChildNode(boardRoot)
        boardRoot.position = boardRestPosition

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.48, alpha: 1)
        ambient.light?.intensity = 380
        scene.rootNode.addChildNode(ambient)
        ambientLightNode = ambient

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
        sun.light?.intensity = 720
        sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred
        sun.light?.orthographicScale = 14
        sun.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.light?.maximumShadowDistance = 40
        sun.light?.shadowRadius = 6
        sun.light?.shadowSampleCount = 8
        sun.light?.shadowColor = UIColor(white: 0, alpha: 0.22)
        sun.eulerAngles = SCNVector3(-0.95, 0.55, 0)
        sun.position = SCNVector3(5, 11, 6)
        scene.rootNode.addChildNode(sun)
        sunLightNode = sun

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 260
        fill.light?.color = UIColor(red: 0.95, green: 0.9, blue: 1, alpha: 1)
        fill.position = SCNVector3(-5, 6, 4)
        scene.rootNode.addChildNode(fill)
        fillLightNode = fill

        let table = SCNBox(width: CGFloat(tableSize), height: 0.12, length: CGFloat(tableSize), chamferRadius: 0.16)
        let wood = PaperStyle.woodMaterial()
        table.materials = [wood, wood, wood, wood, wood, wood]
        tableNode = SCNNode(geometry: table)
        tableNode.position = SCNVector3(0, -0.18, 0)
        tableNode.castsShadow = false
        boardRoot.addChildNode(tableNode)

        for quadrant in Quadrant.allCases {
            let node = makeQuadrant(quadrant)
            quadrantNodes[quadrant] = node
            boardRoot.addChildNode(node)
        }

        cameraNode.camera = SCNCamera()
        cameraNode.camera?.wantsHDR = false
        cameraNode.camera?.wantsExposureAdaptation = false
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 80
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.name = "root"
        fitCamera(to: CGSize(width: 390, height: 520))
    }

    func fitCamera(to viewSize: CGSize) {
        lastViewSize = viewSize
        applyCamera(animated: false)
    }

    private func applyCamera(animated: Bool) {
        guard lastViewSize.width > 8, lastViewSize.height > 8, let camera = cameraNode.camera else { return }
        let t = max(0, min(1, cameraTilt))
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.38
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        cameraNode.position = SCNVector3(0, 13.5 - t * 1.9, 0.05 + t * 4.35)
        cameraNode.look(at: SCNVector3(0, 0, t * 0.18))
        let half = viewFitHalf
        let aspect = Float(lastViewSize.width / lastViewSize.height)
        let corners: [SCNVector3] = [
            SCNVector3(-half, 0, -half),
            SCNVector3(half, 0, -half),
            SCNVector3(-half, 0, half),
            SCNVector3(half, 0, half)
        ]
        var maxTanX: Float = 0.001
        for corner in corners {
            let world = boardRoot.convertVector(corner, to: nil)
            let local = cameraNode.convertPosition(world, from: nil)
            let depth = max(-local.z, 0.05)
            maxTanX = max(maxTanX, abs(local.x) / depth)
        }
        let neededH = 2 * atan(maxTanX)
        let vFromH = 2 * atan(tan(neededH / 2) / max(aspect, 0.2))
        camera.projectionDirection = .vertical
        camera.fieldOfView = CGFloat(vFromH * 180 / Float.pi)
        if animated {
            SCNTransaction.commit()
        }
    }

    private func makeQuadrant(_ quadrant: Quadrant) -> SCNNode {
        let node = SCNNode()
        node.name = "quad_\(quadrant.rawValue)"
        var center = quadrantCenter(quadrant)
        center.y = 0.16
        node.position = center

        let width = CGFloat(cellSize * 3 + sheetPad)
        let top = PaperStyle.graniteMaterial(offset: Float(quadrant.rawValue) * 0.17)
        let edge = PaperStyle.graniteMaterial(dark: true, offset: Float(quadrant.rawValue) * 0.11)
        let sheet = SCNBox(width: width, height: CGFloat(0.28 * slab), length: width, chamferRadius: CGFloat(0.045 * slab))
        sheet.materials = [edge, edge, edge, edge, top, edge]
        let sheetNode = SCNNode(geometry: sheet)
        sheetNode.name = "quad_\(quadrant.rawValue)"
        sheetNode.position.y = 0.1 * tabletThick
        node.addChildNode(sheetNode)

        let shadow = SCNPlane(width: width + CGFloat(0.12 * playScale), height: width + CGFloat(0.12 * playScale))
        let shadowMat = PaperStyle.unlit(UIColor(white: 0.25, alpha: 0.08))
        shadowMat.isDoubleSided = true
        shadow.materials = [shadowMat]
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.name = "quad_shadow"
        shadowNode.eulerAngles.x = -.pi / 2
        shadowNode.position.y = -0.14
        shadowNode.castsShadow = false
        node.addChildNode(shadowNode)
        addGrid(to: node, width: Float(width))

        for localRow in 0..<3 {
            for localCol in 0..<3 {
                let row = quadrant.rowOffset + localRow
                let col = quadrant.colOffset + localCol
                let cellNode = makeCell(row: row, col: col, localRow: localRow, localCol: localCol)
                node.addChildNode(cellNode)
            }
        }
        return node
    }

    private func addGrid(to node: SCNNode, width: Float) {
        let bar: Float = 0.11 * playScale
        let height: Float = 0.07 * slab
        let half = width / 2
        let xs: [Float] = [-(half - bar / 2), -cellSize / 2, cellSize / 2, half - bar / 2]
        let cream = PaperStyle.graniteMaterial(offset: 0.31)
        let edge = PaperStyle.graniteMaterial(dark: true, offset: 0.44)
        for x in xs {
            let geometry = SCNBox(width: CGFloat(bar), height: CGFloat(height), length: CGFloat(width), chamferRadius: 0.02)
            geometry.materials = [edge, edge, edge, edge, cream, edge]
            let barNode = SCNNode(geometry: geometry)
            barNode.position = SCNVector3(x, 0.24 * slab, 0)
            barNode.name = "quad_grid"
            node.addChildNode(barNode)
        }
        for z in xs {
            let geometry = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(bar), chamferRadius: 0.02)
            geometry.materials = [edge, edge, edge, edge, cream, edge]
            let barNode = SCNNode(geometry: geometry)
            barNode.position = SCNVector3(0, 0.24 * slab, z)
            barNode.name = "quad_grid"
            node.addChildNode(barNode)
        }
    }

    private func makeCell(row: Int, col: Int, localRow: Int, localCol: Int) -> SCNNode {
        let node = SCNNode()
        let key = cellKey(row: row, col: col)
        node.name = "cell_\(row)_\(col)"
        let well: Float = cellSize - 0.14 * playScale
        node.position = SCNVector3(
            (Float(localCol) - 1) * cellSize,
            0.165 * slab,
            (Float(localRow) - 1) * cellSize
        )

        let floor = SCNBox(width: CGFloat(well), height: CGFloat(0.02 * slab), length: CGFloat(well), chamferRadius: CGFloat(0.02 * slab))
        floor.materials = [PaperStyle.graniteMaterial(dark: true, offset: 0.22)]
        let floorNode = SCNNode(geometry: floor)
        floorNode.name = "cell_\(row)_\(col)_floor"
        node.addChildNode(floorNode)

        let wallH: Float = 0.055 * slab
        let wallT: Float = 0.02 * playScale
        let wallMat = PaperStyle.graniteMaterial(dark: true, offset: 0.08)
        let north = SCNBox(width: CGFloat(well), height: CGFloat(wallH), length: CGFloat(wallT), chamferRadius: 0.004)
        north.materials = [wallMat]
        let south = SCNBox(width: CGFloat(well), height: CGFloat(wallH), length: CGFloat(wallT), chamferRadius: 0.004)
        south.materials = [wallMat]
        let east = SCNBox(width: CGFloat(wallT), height: CGFloat(wallH), length: CGFloat(well), chamferRadius: 0.004)
        east.materials = [wallMat]
        let west = SCNBox(width: CGFloat(wallT), height: CGFloat(wallH), length: CGFloat(well), chamferRadius: 0.004)
        west.materials = [wallMat]
        let wallY = wallH / 2 + 0.01
        let inset = well / 2 - wallT / 2
        func wallNode(_ geometry: SCNGeometry, x: Float, z: Float) -> SCNNode {
            let wall = SCNNode(geometry: geometry)
            wall.name = "cell_\(row)_\(col)_wall"
            wall.position = SCNVector3(x, wallY, z)
            return wall
        }
        node.addChildNode(wallNode(north, x: 0, z: inset))
        node.addChildNode(wallNode(south, x: 0, z: -inset))
        node.addChildNode(wallNode(east, x: inset, z: 0))
        node.addChildNode(wallNode(west, x: -inset, z: 0))

        cellNodes[key] = node
        return node
    }

    private func updateSeal(key: String, cell: Cell, glow: Bool) {
        sealNodes[key]?.removeFromParentNode()
        sealNodes[key] = nil
        guard cell != .empty, let parent = cellNodes[key] else { return }
        let player: Player = cell == .red ? .red : .indigo
        let color = PaperStyle.waxColor(for: player, palette: sealPalette, skin: boardSkin)
        let motifColor = (sealPalette == .mono && player == .indigo) ? PaperStyle.waxBlack : UIColor(red: 0.95, green: 0.82, blue: 0.45, alpha: 1)
        let seal = clonedSeal(color: color, motifColor: motifColor, glow: glow)
        seal.position.y = 0.07 * playScale
        parent.addChildNode(seal)
        sealNodes[key] = seal
    }

    private func clonedSeal(color: UIColor, motifColor: UIColor, glow: Bool) -> SCNNode {
        if glow {
            return makeSeal(color: color, motifColor: motifColor, glow: true)
        }
        let key = "\(boardSkin)-\(sealPalette.rawValue)-\(color.hash)-\(motifColor.hash)"
        if let template = sealTemplates[key] {
            return template.clone()
        }
        WaxlinePerf.event("seal.template.miss", key)
        let template = makeSeal(color: color, motifColor: motifColor, glow: false)
        sealTemplates[key] = template
        return template.clone()
    }

    private func makeSeal(color: UIColor, motifColor: UIColor, glow: Bool) -> SCNNode {
        let box = SCNBox(
            width: CGFloat(0.62 * playScale),
            height: CGFloat(0.14 * playScale),
            length: CGFloat(0.62 * playScale),
            chamferRadius: CGFloat(0.12 * playScale)
        )
        let material = PaperStyle.waxMaterial(color: color, skin: boardSkin)
        if glow {
            material.emission.contents = color.withAlphaComponent(0.9)
        }
        box.materials = [material]
        let node = SCNNode(geometry: box)

        let motif = SCNShape(path: PaperStyle.starPath(scale: CGFloat(playScale)), extrusionDepth: CGFloat(0.03 * playScale))
        let motifMat = PaperStyle.waxMaterial(color: motifColor, skin: boardSkin)
        motifMat.metalness.contents = 0.35
        motifMat.roughness.contents = 0.28
        if glow {
            motifMat.emission.contents = motifColor.withAlphaComponent(0.85)
        }
        motif.materials = [motifMat]
        let motifNode = SCNNode(geometry: motif)
        motifNode.eulerAngles.x = -.pi / 2
        motifNode.position.y = 0.08 * playScale
        node.addChildNode(motifNode)
        return node
    }

    private func quadrantCenter(_ quadrant: Quadrant) -> SCNVector3 {
        let span = cellSize * 1.5 + gap / 2
        let x: Float = (quadrant == .ne || quadrant == .se) ? span : -span
        let z: Float = (quadrant == .sw || quadrant == .se) ? span : -span
        return SCNVector3(x, 0, z)
    }

    private func cellKey(row: Int, col: Int) -> String { "\(row)_\(col)" }

    private func clearWinHighlight() {
        for node in sealNodes.values {
            node.removeAction(forKey: "winPulse")
            node.opacity = 1
            node.scale = SCNVector3(1, 1, 1)
        }
    }

    private func showWin(line: [Position], model: BoardModel) {
        let keys = Set(line.map { cellKey(row: $0.row, col: $0.col) })
        for (key, node) in sealNodes {
            if keys.contains(key) { continue }
            node.opacity = 0.28
        }
        for position in line {
            let key = cellKey(row: position.row, col: position.col)
            updateSeal(key: key, cell: model.cells[position.row][position.col], glow: true)
            guard let seal = sealNodes[key] else { continue }
            seal.position.y = 0.2 * playScale
            seal.scale = SCNVector3(1.16, 1.16, 1.16)
            let lift = SCNAction.moveBy(x: 0, y: Double(0.07 * playScale), z: 0, duration: 0.42)
            lift.timingMode = .easeInEaseOut
            seal.runAction(.repeatForever(.sequence([lift, lift.reversed()])), forKey: "winPulse")
        }
    }
}
