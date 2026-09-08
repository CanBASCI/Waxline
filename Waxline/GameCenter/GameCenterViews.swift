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

