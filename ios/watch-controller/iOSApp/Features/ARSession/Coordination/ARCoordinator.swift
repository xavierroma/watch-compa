import Foundation
import Combine

// High-level AR session status that coordinates UI and session state
enum ARSessionStatus: Equatable {
    case checkingPrerequisites
    case notSupported
    case cameraNotDetermined
    case cameraDenied
    case missingReferenceImages
    case ready
    case tracking
    case interrupted
    case sessionFailed(String)

    var message: String {
        switch self {
        case .checkingPrerequisites:
            return "Checking camera and AR capabilities…"
        case .notSupported:
            return "AR is not supported on this device."
        case .cameraNotDetermined:
            return "Requesting camera permission…"
        case .cameraDenied:
            return "Camera access denied. Enable it in Settings."
        case .missingReferenceImages:
            return "No AR reference images found in the asset catalog."
        case .ready:
            return "Point your camera at the tag image"
        case .tracking:
            return "Tracking image…"
        case .interrupted:
            return "Session interrupted. Hold on…"
        case .sessionFailed(let msg):
            return "Session failed: \(msg)"
        }
    }
}

// Sink protocol to receive AR status updates from the session
protocol ARStatusSink: AnyObject {
    func didUpdateStatus(_ newStatus: ARSessionStatus)
}

// Proxy that mirrors latest pad coordinates from RemotePads
final class PadCoordinatesProxy: ObservableObject {
    @Published var touchEvent: TouchEvent?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {}
    
    func bindTo<Event: Publisher>(event: Event, on scheduler: RunLoop = .main) where Event.Output == TouchEvent?, Event.Failure == Never {
        
        event
            .throttle(for: .milliseconds(16), scheduler: scheduler, latest: true)
            .sink(receiveValue: { [weak self] newValue in
                if let newValue {
                    self?.touchEvent = newValue
                }
            })
            .store(in: &cancellables)
}
}

