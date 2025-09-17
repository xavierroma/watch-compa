//
//  WatchRelay.swift
//  watch-controller
//
//  Created by Xavier Roma on 17/9/25.
//

import Foundation
import WatchConnectivity
import Combine

final class WatchRelay: NSObject, ObservableObject, WCSessionDelegate {
    
    static let shared = WatchRelay()
    private let s = WCSession.isSupported() ? WCSession.default : nil

    // Optional: expose reachability to UI
    @Published var isReachable: Bool = false
    
    func activate() {
        guard let s else { return }
        s.delegate = self
        s.activate()
        // Initialize reachability state if already available
        isReachable = s.isReachable
    }

    // Upstream: send immediately if reachable, else queue
    func send(_ e: TouchEvent) {
        guard let s else {
            print("no session, can't send")
            return
        }
        let payload: [String: Any] = ["type": "padCoord", "x": e.x, "y": e.y, "t": e.t]
        if s.isReachable {
            print("Sending")
            s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            print("not reachable, queuing")
            s.transferUserInfo(payload)
        }
    }

    // Downstream from phone/server
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // update UI / state
        print("downlink:", message)
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        print("downlink (queued):", userInfo)
    }

    // Required: activation completion (both platforms)
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    // Required: reachability changes (watchOS)
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isReachable = session.isReachable
        }
    }
}
