import SwiftUI

struct TouchPadView: View {
    @State private var lastSent: CFAbsoluteTime = 0

    // Track the current normalized touch location (0...1). nil when no touch yet.
    @State private var currentX: Double?
    @State private var currentY: Double?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // Base pad shape
                let padCorner: CGFloat = 8
                let padShape = RoundedRectangle(cornerRadius: padCorner, style: .continuous)

                padShape
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        padShape
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    )

                // Connection status pill
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(WatchRelay.shared.isReachable ? .green : .red)
                            .frame(width: 8, height: 8)
                    }
                    .padding(4)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 4)

                // Cartesian overlays: dashed axis lines and active point
                if let nx = currentX, let ny = currentY {
                    let px = CGFloat(nx) * max(1, size.width)
                    // Origin is bottom-left for ny; convert to top-left pixel space for drawing
                    let py = (1 - CGFloat(ny)) * max(1, size.height)

                    // Dotted lines from (x,0)->(x,y) and (0,y)->(x,y)
                    // Vertical line segment
                    Path { path in
                        path.move(to: CGPoint(x: px, y: size.height))
                        path.addLine(to: CGPoint(x: px, y: py))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.blue.opacity(0.7))

                    // Horizontal line segment
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: py))
                        path.addLine(to: CGPoint(x: px, y: py))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.blue.opacity(0.7))

                    // Active point
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                        .position(x: max(0, min(size.width, px)),
                                  y: max(0, min(size.height, py)))
                        .shadow(color: .blue.opacity(0.4), radius: 2, x: 0, y: 0)
                }
            }
            // Constrain hit testing to the rounded rectangle only
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            // Use simultaneousGesture so TabView can still detect its page swipe gestures at edges
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Ignore touches that begin outside our bounds
                        guard value.startLocation.x >= 0, value.startLocation.x <= size.width,
                              value.startLocation.y >= 0, value.startLocation.y <= size.height else {
                            return
                        }
                        let nx = clamp01(value.location.x / max(1, size.width))
                        // Flip y so that 0 is bottom, 1 is top (bottom-left origin)
                        let nyTopLeft = clamp01(value.location.y / max(1, size.height))
                        let ny = 1 - nyTopLeft
                        currentX = nx
                        currentY = ny
                        throttleAndSend(x: nx, y: ny)
                    }
                    .onEnded { value in
                        guard value.startLocation.x >= 0, value.startLocation.x <= size.width,
                              value.startLocation.y >= 0, value.startLocation.y <= size.height else {
                            return
                        }
                        let nx = clamp01(value.location.x / max(1, size.width))
                        let nyTopLeft = clamp01(value.location.y / max(1, size.height))
                        let ny = 1 - nyTopLeft
                        currentX = nx
                        currentY = ny
                        Task {
                            WatchRelay.shared.send(TouchEvent(x: nx, y: ny))
                        }
                    }
            )
        }
        // Avoid extra padding that could expand the gesture hit area beyond the visual pad
        .padding(6)
    }

    private func clamp01(_ v: CGFloat) -> Double { Double(max(0, min(1, v))) }


    private func throttleAndSend(x: Double, y: Double) {
        // ~60 Hz throttle
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastSent >= 1.0 / 60.0 {
            lastSent = now
            Task { WatchRelay.shared.send(TouchEvent(x: x, y: y)) }
        }
    }
}
