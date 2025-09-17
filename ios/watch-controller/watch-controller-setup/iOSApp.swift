import SwiftUI

@main
struct WatchController_iOSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var configStore = AppGroupConfigStore(appGroupID: "compa.com.x.watchcontroller")

    var body: some Scene {
        WindowGroup {
            NavigationView {
                SettingsView()
            }
            .environmentObject(configStore)
            .task {
                await configStore.ensureDefaults()
                // Optionally start immediately on launch with a default or configured URL
                startPhoneSocketBridgeIfPossible()
            }
            .onChange(of: scenePhase) { oldValue, newValue in
                if newValue == .active {
                    startPhoneSocketBridgeIfPossible()
                }
            }
        }
    }

    private func startPhoneSocketBridgeIfPossible() {
        let addr = self.configStore.currentConfig().serverAddress
        if let url = URL(string: "https://cf0a7d8ac71e.ngrok-free.app/ingest/pad-coordinates/s") {
            PhoneSocketBridge.shared.start(url: url)
        }
    }
}
