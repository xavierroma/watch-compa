import Foundation

public struct TouchEvent: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let t: TimeInterval

    public init(x: Double, y: Double, t: TimeInterval = Date().timeIntervalSince1970) {
        self.x = x
        self.y = y
        self.t = t
    }
    
    public static func FromDict(_ dict: [String: Any]) throws -> Self {
        guard dict["x"] != nil, dict["y"] != nil, dict["t"] != nil else {
            throw NSError(domain: "com.touch.event", code: 0, userInfo: nil)
        }
        let x = dict["x"] as! Double
        let y = dict["y"] as! Double
        let t = dict["t"] as! Double
        return Self(x: x, y: y, t: t)
    }
    
    public func toDict() -> [String: Any] {
        ["x": "\(x)", "y": "\(y)", "t": "\(t)"]
    }
}

