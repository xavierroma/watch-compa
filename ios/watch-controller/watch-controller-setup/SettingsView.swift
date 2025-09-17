import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var configStore: AppGroupConfigStore

    @State private var serverAddress: String = ""
    @State private var deviceID: String = ""

    var body: some View {
        Form {
            Section(header: Text("WebSocket Server")) {
                TextField("http://host:port", text: $serverAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled(true)
                Text(validatedPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("Device ID")) {
                TextField("Device ID", text: $deviceID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("Use This iPhone ID") {
                    if let id = UIDevice.current.identifierForVendor?.uuidString {
                        deviceID = id
                    }
                }
            }

            Section {
                Button("Save") {
                    Task {
                        let config = AppConfig(serverAddress: normalizeServerAddress(serverAddress),
                                               deviceID: deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppConfig.defaultDeviceID() : deviceID)
                        await configStore.save(config)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Controller Settings")
        .task {
            let cfg = configStore.currentConfig()
            serverAddress = cfg.serverAddress
            deviceID = cfg.deviceID
        }
    }

    private var validatedPreview: String {
        let normalized = normalizeServerAddress(serverAddress)
        let tempConfig = AppConfig(serverAddress: normalized, deviceID: deviceID.isEmpty ? AppConfig.defaultDeviceID() : deviceID)
        return "WebSocket: \(tempConfig.ingestWebSocketURL()?.absoluteString ?? "invalid")"
    }

    private func normalizeServerAddress(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "https://echo.websocket.org" }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
            s = "http://\(s)"
        }
        return s
    }
}


#Preview {
    SettingsView()
}
