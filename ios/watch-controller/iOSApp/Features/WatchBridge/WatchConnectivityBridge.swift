//
//  PhoneSocketBridge.swift
//  watch-controller
//

import Foundation
import Starscream
import WatchConnectivity
import Combine

final class PhoneSocketBridge: NSObject, ObservableObject {
    static let shared = PhoneSocketBridge()

    private var socket: WebSocket?
    private var isConnected = false

    // Publish latest normalized coordinates from the server
    @Published var latestCoordinateEvent: TouchEvent?

    // Configure once at app launch
    func start(url: URL) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        socket = WebSocket(request: req)
        socket?.delegate = self
        socket?.connect()
        PhoneWC.shared.activate()
    }

    // Watch -> Server
    func sendUpstream(_ dict: [String: Any]) {
        guard isConnected,
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let event = try? TouchEvent.FromDict(dict) else { return }
        
        guard let type = dict["type"] as? String, type == "padCoord" else {
            print("wrong type")
            return
        }
        
        DispatchQueue.main.async {
            self.latestCoordinateEvent = event
        }
        socket?.write(data: data)
        
    }

    // Server -> Watch
    private func forwardDownstreamToWatch(_ dict: [String: Any]) {
        PhoneWC.shared.pushToWatch(dict)
    }

    // Parse downstream pad coordinates and publish locally for iOS AR view
    private func handleDownstreamDict(_ dict: [String: Any]) {
        // Forward to watch regardless
        forwardDownstreamToWatch(dict)
    }
}

extension PhoneSocketBridge: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected:
            isConnected = true

        case .disconnected, .cancelled, .error:
            isConnected = false
            // simple backoff
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                client.connect()
            }

        case .binary(let data):
            if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                handleDownstreamDict(obj)
            }

        case .text(let text):
            if let d = text.data(using: .utf8),
               let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                handleDownstreamDict(obj)
            }

        default:
            break
        }
    }
}

// Minimal WCSession wrapper on iOS
final class PhoneWC: NSObject, WCSessionDelegate {
    static let shared = PhoneWC()
    private let s = WCSession.isSupported() ? WCSession.default : nil

    func activate() {
        guard let s else { return }
        s.delegate = self
        s.activate()
    }

    // From Watch -> forward to WS
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        PhoneSocketBridge.shared.sendUpstream(message)
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        PhoneSocketBridge.shared.sendUpstream(userInfo)
    }

    // To Watch (best-effort immediate, else queued)
    func pushToWatch(_ payload: [String: Any]) {
        guard let s else { return }
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            s.transferUserInfo(payload)
        }
    }

    // required stubs
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}

// Minimal WCSession wrapper on iOS stays the same…

