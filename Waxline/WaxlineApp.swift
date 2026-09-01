import SwiftUI

@main
struct WaxlineApp: App {
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
