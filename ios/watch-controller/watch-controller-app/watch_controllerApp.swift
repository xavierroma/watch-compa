//
//  watch_controllerApp.swift
//  watch-controller Watch App
//
//  Created by Xavier Roma on 17/9/25.
//

import SwiftUI

@main
struct watch_controller_Watch_AppApp: App {
    @StateObject private var configStore = AppGroupConfigStore(appGroupID: "compa.com.x.watchcontroller")
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(configStore)
                .task {
                    WatchRelay.shared.activate()
                    await configStore.ensureDefaults()
                }
        }
    }
}

