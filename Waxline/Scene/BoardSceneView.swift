import SwiftUI
@preconcurrency import SceneKit

struct BoardSceneView: UIViewRepresentable {
    var controller: BoardSceneController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> BoardSCNView {
        let view = BoardSCNView()
        view.scene = controller.scene
        view.backgroundColor = PaperStyle.cream
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.isPlaying = true
        view.clipsToBounds = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        let pan = UIPanGestureRecognizer(target: controller, action: #selector(BoardSceneController.handleBoardPan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(tap)
        controller.scnView = view
        view.pointOfView = controller.scene.rootNode.childNode(withName: "camera", recursively: true)
        view.onLayout = { [weak controller] size in
            controller?.fitCamera(to: size)
        }
        view.onTouchBegan = { [weak controller, weak view] point in
            guard let view else { return }
            controller?.handleTouchBegan(at: point, in: view)
        }
        view.onTouchEnded = { [weak controller] in
            controller?.handleTouchEnded()
        }
        return view
    }

    func updateUIView(_ uiView: BoardSCNView, context: Context) {
        context.coordinator.controller = controller
        uiView.pointOfView = controller.scene.rootNode.childNode(withName: "camera", recursively: true)
    }

    final class Coordinator {
        var controller: BoardSceneController

        init(controller: BoardSceneController) {
            self.controller = controller
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            controller.handleTap(at: gesture.location(in: view), in: view)
        }
    }
}

final class BoardSCNView: SCNView {
    var onLayout: ((CGSize) -> Void)?
    var onTouchBegan: ((CGPoint) -> Void)?
    var onTouchEnded: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds.size)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if let point = touches.first?.location(in: self) {
            onTouchBegan?(point)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        onTouchEnded?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        onTouchEnded?()
    }
}
