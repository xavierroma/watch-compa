//
//  ARView.swift
//  watch-controller
//
//  Created by Xavier Roma on 17/9/25.
//
import SwiftUI
import ARKit
import RealityKit
import UIKit
import AVFoundation
import Combine

struct ARView: View {
    @State private var status: ARSessionStatus = .checkingPrerequisites

    var body: some View {
        ZStack(alignment: .top) {
            ARImageOverlayViewRepresentable(status: $status)

            // Overlay HUD
            VStack(spacing: 8) {
                HStack {
                    Text(status.message)
                        .font(.footnote)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }

                if case .cameraDenied = status {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .ignoresSafeArea()
    }
}

struct ARImageOverlayViewRepresentable: UIViewRepresentable {
    @Binding var status: ARSessionStatus

    func makeCoordinator() -> Coordinator {
        Coordinator(status: $status)
    }

    func makeUIView(context: Context) -> OverlayARView {
        let view = OverlayARView(frame: .zero, statusSink: context.coordinator)
        view.prepareAndStartSession()
        return view
    }

    func updateUIView(_ uiView: OverlayARView, context: Context) {
        // No-op; updates come from the bridge subscription
    }

    final class Coordinator: ARStatusSink {
        @Binding var status: ARSessionStatus

        init(status: Binding<ARSessionStatus>) {
            self._status = status
        }

        func didUpdateStatus(_ newStatus: ARSessionStatus) {
            DispatchQueue.main.async {
                self.status = newStatus
            }
        }
    }
}
