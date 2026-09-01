@preconcurrency import SceneKit
import simd
import UIKit

@MainActor
final class BoardSceneController: NSObject {
    let scene = SCNScene()
    weak var scnView: SCNView?

    var onCellTap: ((Position) -> Void)?
    var onQuadrantTap: ((Quadrant?) -> Void)?
    var onRotateGesture: ((Bool) -> Void)?

    private let boardRoot = SCNNode()
    private var quadrantNodes: [Quadrant: SCNNode] = [:]
    private var cellNodes: [String: SCNNode] = [:]
    private var sealNodes: [String: SCNNode] = [:]

    private var allowsCellTaps = true
    private var allowsQuadrantTaps = false
    private var selectedQuadrant: Quadrant?
    private var isAnimating = false
    private var rotationCompletion: (() -> Void)?
    private var cameraNode = SCNNode()
    private var panStartAngle: Float = 0
    private var restYaw: Float = 0
    private var cameraTilt: Float = 1
    private var panStartTabletYaw: Float = 0
    private var panTabletCenter = SIMD2<Float>.zero
    private var panGrabCorner = SIMD2<Float>.zero
    private var panStartBoardXZ = SIMD2<Float>.zero
    private var panTabletDelta: Float = 0
    private var lastViewSize = CGSize(width: 390, height: 520)

    private let cellSize: Float = 0.92
    private let gap: Float = 0.16
    private let tableSize: Float = 7.2

    override init() {
        super.init()
        buildScene()
    }

    func setInteraction(canPlace: Bool, canSelectQuadrant: Bool) {
        allowsCellTaps = canPlace && !isAnimating
        allowsQuadrantTaps = canSelectQuadrant && !isAnimating
        for node in quadrantNodes.values {
            node.removeAction(forKey: "inviteRotate")
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.32
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        for (quadrant, node) in quadrantNodes {
            let selected = selectedQuadrant == quadrant && canSelectQuadrant
            node.position.y = selected ? 0.58 : 0.16
            node.scale = selected ? SCNVector3(1.045, 1.045, 1.045) : SCNVector3(1, 1, 1)
        }
        SCNTransaction.commit()
        if canSelectQuadrant, selectedQuadrant == nil {
            startRotateInvite()
        }
    }

    private func startRotateInvite() {
        for (quadrant, node) in quadrantNodes {
            let x = node.position.x
            let z = node.position.z
            let delay = SCNAction.wait(duration: 0.08 * Double(quadrant.rawValue))
            let up = SCNAction.move(to: SCNVector3(x, 0.34, z), duration: 0.52)
            up.timingMode = .easeInEaseOut
            let down = SCNAction.move(to: SCNVector3(x, 0.16, z), duration: 0.52)
            down.timingMode = .easeInEaseOut
            let twoLifts = SCNAction.sequence([up, down, up, down])
            let rest = SCNAction.wait(duration: 5)
            let loop = SCNAction.repeatForever(.sequence([twoLifts, rest]))
            node.runAction(.sequence([delay, loop]), forKey: "inviteRotate")
        }
    }

    func syncBoard(_ model: BoardModel, winningLine: [Position]?) {
        for row in 0..<6 {
            for col in 0..<6 {
                let key = cellKey(row: row, col: col)
                updateSeal(key: key, cell: model.cells[row][col], glow: false)
            }
        }
        if let winningLine {
            for position in winningLine {
                updateSeal(key: cellKey(row: position.row, col: position.col), cell: model.cells[position.row][position.col], glow: true)
            }
        }
    }

    func dropSeal(at position: Position, player: Player) {
        let key = cellKey(row: position.row, col: position.col)
        updateSeal(key: key, cell: player.cell, glow: false)
        if let node = sealNodes[key] {
            node.position.y = 0.7
            node.runAction(.moveBy(x: 0, y: -0.63, z: 0, duration: 0.22))
        }
    }

    func animateRotation(quadrant: Quadrant, clockwise: Bool, model: BoardModel, completion: @escaping () -> Void) {
        guard let node = quadrantNodes[quadrant] else {
            completion()
            return
        }
        isAnimating = true
        allowsCellTaps = false
        allowsQuadrantTaps = false
        for node in quadrantNodes.values {
            node.removeAction(forKey: "inviteRotate")
        }
        rotationCompletion = completion
        let target: Float = clockwise ? -.pi / 2 : .pi / 2
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
        quadrantNodes[quadrant]?.eulerAngles.y = 0
        syncBoard(model, winningLine: nil)
        selectedQuadrant = nil
        isAnimating = false
        let done = rotationCompletion
        rotationCompletion = nil
        done?()
    }

    func setPerspective3D(_ is3D: Bool) {
        cameraTilt = is3D ? 1 : 0
        applyCamera(animated: true)
    }

    func beginPan() {
        boardRoot.position = SCNVector3Zero
        panStartAngle = restYaw
        panStartTabletYaw = 0
        panTabletDelta = 0
    }

    private func beginTablePan(at viewPoint: CGPoint, in view: SCNView) {
        boardRoot.position = SCNVector3Zero
        panStartAngle = restYaw
        panTabletDelta = 0
        let origin = boardRoot.convertPosition(SCNVector3Zero, to: nil)
        let center = SIMD2(origin.x, origin.z)
        panTabletCenter = center
        let point = worldXZ(from: viewPoint, in: view) ?? center
        panStartBoardXZ = point
        panGrabCorner = nearestTableCorner(to: point)
    }

    private func updateTablePan(at viewPoint: CGPoint, in view: SCNView) {
        guard !isAnimating else { return }
        guard let now = worldXZ(from: viewPoint, in: view) else { return }
        boardRoot.position = SCNVector3Zero
        let grab = panGrabCorner - panTabletCenter
        let dragged = panGrabCorner + (now - panStartBoardXZ) - panTabletCenter
        var delta = signedAngle(from: grab, to: dragged)
        let limit = Float.pi / 2
        delta = min(max(delta, -limit), limit)
        panTabletDelta = delta
        boardRoot.eulerAngles.y = panStartAngle + delta
    }

    private func endTablePan() {
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
        guard let quadrant = selectedQuadrant, let node = quadrantNodes[quadrant] else { return }
        panStartTabletYaw = node.eulerAngles.y
        panTabletDelta = 0
        let center = SIMD2(node.position.x, node.position.z)
        panTabletCenter = center
        let half = (cellSize * 3 + 0.08) / 2
        let point = boardXZ(from: viewPoint, in: view) ?? center
        panStartBoardXZ = point
        panGrabCorner = nearestSquareCorner(center: center, half: half, to: point)
    }

    private func updateTabletPan(at viewPoint: CGPoint, in view: SCNView) {
        guard !isAnimating, let quadrant = selectedQuadrant, let node = quadrantNodes[quadrant] else { return }
        guard let now = boardXZ(from: viewPoint, in: view) else { return }
        let grab = panGrabCorner - panTabletCenter
        let dragged = panGrabCorner + (now - panStartBoardXZ) - panTabletCenter
        var delta = signedAngle(from: grab, to: dragged)
        let limit = Float.pi / 2
        delta = min(max(delta, -limit), limit)
        panTabletDelta = delta
        node.eulerAngles.y = panStartTabletYaw + delta
    }

    private func endTabletPan() {
        guard !isAnimating else { return }
        if abs(panTabletDelta) > 0.28 {
            onRotateGesture?(panTabletDelta < 0)
        } else if let quadrant = selectedQuadrant, let node = quadrantNodes[quadrant] {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.38
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            node.eulerAngles.y = 0
            SCNTransaction.commit()
        }
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

    private func nearestTableCorner(to point: SIMD2<Float>) -> SIMD2<Float> {
        let half = tableSize / 2
        let locals = [
            SCNVector3(half, 0, half),
            SCNVector3(half, 0, -half),
            SCNVector3(-half, 0, half),
            SCNVector3(-half, 0, -half)
        ]
        let corners = locals.map { local -> SIMD2<Float> in
            let world = boardRoot.convertPosition(local, to: nil)
            return SIMD2(world.x, world.z)
        }
        return corners.min(by: { simd_distance($0, point) < simd_distance($1, point) }) ?? corners[0]
    }

    private func nearestSquareCorner(center: SIMD2<Float>, half: Float, to point: SIMD2<Float>) -> SIMD2<Float> {
        let corners = [
            SIMD2(center.x + half, center.y + half),
            SIMD2(center.x + half, center.y - half),
            SIMD2(center.x - half, center.y + half),
            SIMD2(center.x - half, center.y - half)
        ]
        return corners.min(by: { simd_distance($0, point) < simd_distance($1, point) }) ?? corners[0]
    }

    private func signedAngle(from a: SIMD2<Float>, to b: SIMD2<Float>) -> Float {
        let den = simd_length(a) * simd_length(b)
        guard den > 0.0001 else { return 0 }
        let cross = a.y * b.x - a.x * b.y
        let dot = simd_dot(a, b)
        return atan2(cross, dot)
    }

    @objc func handleBoardPan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view as? SCNView else { return }
        let location = gesture.location(in: view)
        let rotatingTablet = allowsQuadrantTaps && selectedQuadrant != nil
        switch gesture.state {
        case .began:
            beginPan()
            if rotatingTablet {
                beginTabletPan(at: location, in: view)
            } else {
                beginTablePan(at: location, in: view)
            }
        case .changed:
            if rotatingTablet {
                updateTabletPan(at: location, in: view)
            } else {
                updateTablePan(at: location, in: view)
            }
        case .ended, .cancelled, .failed:
            if rotatingTablet {
                endTabletPan()
            } else {
                endTablePan()
            }
        default:
            break
        }
    }

    private func snapBoard(to yaw: Float) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.38
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        boardRoot.position = SCNVector3Zero
        boardRoot.eulerAngles.y = yaw
        SCNTransaction.commit()
    }

    func handleTap(at viewPoint: CGPoint, in view: SCNView) {
        guard !isAnimating else { return }
        guard let world = boardPoint(from: viewPoint, in: view) else { return }
        if allowsCellTaps, let position = cell(at: world) {
            onCellTap?(position)
            return
        }
        if allowsQuadrantTaps, let quadrant = quadrant(at: world) {
            if selectedQuadrant == quadrant {
                selectedQuadrant = nil
            } else {
                selectedQuadrant = quadrant
            }
            setInteraction(canPlace: false, canSelectQuadrant: true)
            onQuadrantTap?(selectedQuadrant)
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
        guard let position = cell(at: world) else { return nil }
        if position.row < 3 {
            return position.col < 3 ? .nw : .ne
        }
        return position.col < 3 ? .sw : .se
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

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.48, alpha: 1)
        ambient.light?.intensity = 380
        scene.rootNode.addChildNode(ambient)

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

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 260
        fill.light?.color = UIColor(red: 0.95, green: 0.9, blue: 1, alpha: 1)
        fill.position = SCNVector3(-5, 6, 4)
        scene.rootNode.addChildNode(fill)

        let table = SCNBox(width: CGFloat(tableSize), height: 0.12, length: CGFloat(tableSize), chamferRadius: 0.08)
        let wood = PaperStyle.woodMaterial()
        table.materials = [wood, wood, wood, wood, wood, wood]
        let tableNode = SCNNode(geometry: table)
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
        let half = tableSize / 2
        let aspect = Float(lastViewSize.width / lastViewSize.height)
        let corners: [SCNVector3] = [
            SCNVector3(-half, 0, -half),
            SCNVector3(half, 0, -half),
            SCNVector3(-half, 0, half),
            SCNVector3(half, 0, half)
        ]
        var maxTanX: Float = 0.001
        for corner in corners {
            let world = boardRoot.convertPosition(corner, to: nil)
            let local = cameraNode.convertPosition(world, from: nil)
            let depth = max(-local.z, 0.05)
            maxTanX = max(maxTanX, abs(local.x) / depth)
        }
        // Fill the view width so table left/right meet the frame; uniform scale via FOV only.
        let neededH = 2 * atan(maxTanX * 1.02)
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

        let width = CGFloat(cellSize * 3 + 0.08)
        let top = PaperStyle.graniteMaterial(offset: Float(quadrant.rawValue) * 0.17)
        let edge = PaperStyle.graniteMaterial(dark: true, offset: Float(quadrant.rawValue) * 0.11)
        let sheet = SCNBox(width: width, height: 0.2, length: width, chamferRadius: 0.045)
        sheet.materials = [edge, edge, edge, edge, top, edge]
        let sheetNode = SCNNode(geometry: sheet)
        sheetNode.name = "quad_\(quadrant.rawValue)"
        sheetNode.position.y = 0.1
        node.addChildNode(sheetNode)

        let shadow = SCNPlane(width: width + 0.12, height: width + 0.12)
        let shadowMat = PaperStyle.unlit(UIColor(white: 0.25, alpha: 0.08))
        shadowMat.isDoubleSided = true
        shadow.materials = [shadowMat]
        let shadowNode = SCNNode(geometry: shadow)
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
        let bar: Float = 0.11
        let height: Float = 0.07
        let half = width / 2
        let xs: [Float] = [-(half - bar / 2), -cellSize / 2, cellSize / 2, half - bar / 2]
        let cream = PaperStyle.graniteMaterial(offset: 0.31)
        let edge = PaperStyle.graniteMaterial(dark: true, offset: 0.44)
        for x in xs {
            let geometry = SCNBox(width: CGFloat(bar), height: CGFloat(height), length: CGFloat(width), chamferRadius: 0.02)
            geometry.materials = [edge, edge, edge, edge, cream, edge]
            let barNode = SCNNode(geometry: geometry)
            barNode.position = SCNVector3(x, 0.24, 0)
            barNode.name = node.name
            node.addChildNode(barNode)
        }
        for z in xs {
            let geometry = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(bar), chamferRadius: 0.02)
            geometry.materials = [edge, edge, edge, edge, cream, edge]
            let barNode = SCNNode(geometry: geometry)
            barNode.position = SCNVector3(0, 0.24, z)
            barNode.name = node.name
            node.addChildNode(barNode)
        }
    }

    private func makeCell(row: Int, col: Int, localRow: Int, localCol: Int) -> SCNNode {
        let node = SCNNode()
        let key = cellKey(row: row, col: col)
        node.name = "cell_\(row)_\(col)"
        let well: Float = cellSize - 0.14
        node.position = SCNVector3(
            (Float(localCol) - 1) * cellSize,
            0.165,
            (Float(localRow) - 1) * cellSize
        )

        let floor = SCNBox(width: CGFloat(well), height: 0.02, length: CGFloat(well), chamferRadius: 0.02)
        floor.materials = [PaperStyle.graniteMaterial(dark: true, offset: 0.22)]
        let floorNode = SCNNode(geometry: floor)
        floorNode.name = "cell_\(row)_\(col)"
        node.addChildNode(floorNode)

        let wallH: Float = 0.055
        let wallT: Float = 0.02
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
            wall.name = "cell_\(row)_\(col)"
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
        let color = cell == .red ? PaperStyle.waxRed : PaperStyle.waxIndigo
        let seal = makeSeal(color: color, glow: glow)
        seal.position.y = 0.07
        parent.addChildNode(seal)
        sealNodes[key] = seal
    }

    private func makeSeal(color: UIColor, glow: Bool) -> SCNNode {
        let box = SCNBox(width: 0.62, height: 0.14, length: 0.62, chamferRadius: 0.12)
        let material = PaperStyle.waxMaterial(color: color)
        if glow {
            material.emission.contents = color.withAlphaComponent(0.55)
        }
        box.materials = [material]
        let node = SCNNode(geometry: box)

        let motif = SCNShape(path: PaperStyle.starPath(), extrusionDepth: 0.03)
        let motifMat = PaperStyle.waxMaterial(color: UIColor(red: 0.95, green: 0.82, blue: 0.45, alpha: 1))
        motifMat.metalness.contents = 0.35
        motifMat.roughness.contents = 0.28
        if glow {
            motifMat.emission.contents = UIColor(red: 0.95, green: 0.82, blue: 0.45, alpha: 0.45)
        }
        motif.materials = [motifMat]
        let motifNode = SCNNode(geometry: motif)
        motifNode.eulerAngles.x = -.pi / 2
        motifNode.position.y = 0.08
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
}
