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
}

