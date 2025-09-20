import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TouchPadView()
                .tabItem { Label("Pad", systemImage: "hand.point.up.left.fill") }

            ConnectionView()
                .tabItem { Label("Conn", systemImage: "dot.radiowaves.left.and.right") }
        }
    }
}

struct ConnectionView: View {
    @EnvironmentObject private var configStore: AppGroupConfigStore

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
                Text(statusText(WatchRelay.shared.isReachable))
                    .font(.footnote)
            }
        }
        .padding()
    }

    private func colorForStatus(_ isReachable: Bool) -> Color {
        if isReachable {
            return .green
        }
        return .red
    }

    private func statusText(_ isReachable: Bool) -> String {
        if isReachable {
            return "Connected"
        }
        return "Disconnected"
    }
}

#Preview {
    ContentView()
        .environmentObject(AppGroupConfigStore(appGroupID: "compa.com.x.watchcontroller"))
}

