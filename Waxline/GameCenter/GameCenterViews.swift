import GameKit
import SwiftUI

struct GameCenterAuthPresenter: UIViewControllerRepresentable {
    var viewController: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if uiViewController.presentedViewController == nil {
            uiViewController.present(viewController, animated: true)
        }
    }
}

struct TurnBasedMatchmakerView: UIViewControllerRepresentable {
    var onMatch: (GKTurnBasedMatch) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMatch: onMatch, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> GKTurnBasedMatchmakerViewController {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.defaultNumberOfPlayers = 2
        let controller = GKTurnBasedMatchmakerViewController(matchRequest: request)
        controller.turnBasedMatchmakerDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: GKTurnBasedMatchmakerViewController, context: Context) {}

    final class Coordinator: NSObject, GKTurnBasedMatchmakerViewControllerDelegate {
        var onMatch: (GKTurnBasedMatch) -> Void
        var onCancel: () -> Void

        init(onMatch: @escaping (GKTurnBasedMatch) -> Void, onCancel: @escaping () -> Void) {
            self.onMatch = onMatch
            self.onCancel = onCancel
        }

        func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
            viewController.dismiss(animated: true)
            onCancel()
        }

        func turnBasedMatchmakerViewController(
            _ viewController: GKTurnBasedMatchmakerViewController,
            didFailWithError error: Error
        ) {
            viewController.dismiss(animated: true)
            onCancel()
        }
    }
}
