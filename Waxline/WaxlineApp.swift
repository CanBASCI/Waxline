import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct WaxlineApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = SettingsStore()
    @State private var gameCenter = GameCenterService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(gameCenter)
                .preferredColorScheme(.light)
                .tint(Theme.waxRed)
        }
    }
}
