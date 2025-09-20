import Foundation
#if os(iOS)
import UIKit
#endif
#if os(watchOS)
import WatchKit
#endif

public struct AppConfig: Codable, Equatable {
    public var serverAddress: String // http:// or https:// host:port
    public var deviceID: String

    public init(serverAddress: String, deviceID: String) {
        self.serverAddress = serverAddress
        self.deviceID = deviceID
    }

    public static func defaultConfig() -> AppConfig {
        AppConfig(
            serverAddress: "https://echo.websocket.org",
            deviceID: Self.defaultDeviceID()
        )
    }

    public static func defaultDeviceID() -> String {
        #if os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #elseif os(watchOS)
        return WKInterfaceDevice.current().identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        return UUID().uuidString
        #endif
    }

    public func ingestWebSocketURL() -> URL? {
        // Convert http(s)://host[:port][/path] to ws(s)://host[:port][/path]/ingest/{deviceID}
        guard let base = URL(string: serverAddress) else { return nil }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)

        if comps?.scheme == "https" {
            comps?.scheme = "wss"
        } else {
            comps?.scheme = "ws"
        }

        let existingPath = comps?.path ?? ""
        let normalizedExisting = existingPath.hasSuffix("/") ? String(existingPath.dropLast()) : existingPath
        let path = normalizedExisting + "/ingest/pad-coordinates/\(deviceID)"
        comps?.path = path

        return comps?.url
    }
}

