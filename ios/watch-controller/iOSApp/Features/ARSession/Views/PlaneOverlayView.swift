import SwiftUI

struct PlaneOverlayView: View {
    @ObservedObject var proxy: PadCoordinatesProxy

    init(proxy: PadCoordinatesProxy) {
        self.proxy = proxy
    }

    var body: some View {
        GeometryReader { proxyGeo in
            let size = proxyGeo.size
            ZStack {
                // Slight glassy tint
                Color.white.opacity(0.06)

                // Outer rounded square border
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white, lineWidth: 4)
                    .shadow(color: .white.opacity(0.6), radius: 2, x: 0, y: 0)

                // Dashed crosshair in the middle
                Path { path in
                    let cx = size.width / 2
                    let cy = size.height / 2
                    path.move(to: CGPoint(x: cx, y: 0))
                    path.addLine(to: CGPoint(x: cx, y: size.height))
                    path.move(to: CGPoint(x: 0, y: cy))
                    path.addLine(to: CGPoint(x: size.width, y: cy))
                }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                .foregroundStyle(Color.white.opacity(0.7))

                if let nx = proxy.touchEvent?.x, let ny = proxy.touchEvent?.y {
                    let padding: CGFloat = 14 // keep inside border
                    let px = CGFloat(nx) * max(1, size.width)
                    let py = (1 - CGFloat(ny)) * max(1, size.height)
                    let clampedPoint = CGPoint(
                        x: max(padding, min(size.width - padding, px)),
                        y: max(padding, min(size.height - padding, py))
                    )

                    // 2D cursor dot (ring + fill)
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 3)
                        .background(
                            Circle().fill(Color.white.opacity(0.75))
                        )
                        .frame(width: 12, height: 12)
                        .position(x: clampedPoint.x, y: clampedPoint.y)
                        .shadow(color: .white.opacity(0.35), radius: 2.5, x: 0, y: 0)
                        .animation(.easeOut(duration: 0.05), value: clampedPoint)
                } else {
                    let cx = size.width / 2
                    let cy = size.height / 2
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 3)
                        .background(
                            Circle().fill(Color.white.opacity(0.65))
                        )
                        .frame(width: 12, height: 12)
                        .position(x: cx, y: cy)
                }
            }
        }
    }
}



