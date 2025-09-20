//
//  ContentView.swift
//  watch-controller-setup
//
//  Created by Xavier Roma on 17/9/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SettingsView()
                .tabItem { Label("Settings", systemImage: "hand.point.up.left.fill") }
            ARView()
                .tabItem { Label("AR", systemImage: "hand.point.up.left.fill") }
        }
    }
}

#Preview {
    ContentView()
}
