//
//  androidconnectApp.swift
//  androidconnect
//
//  Local-first link between this Mac and an Android phone. LAN only, end-to-end encrypted.
//

import AppKit
import SwiftUI

@main
struct androidconnectApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // The primary surface is a dedicated panel; the menu-bar item is a compact companion.
        Window("AndroidConnect", id: "main") {
            DashboardView(model: model)
        }
        .defaultSize(width: 400, height: 600)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window("Pair a phone", id: "pair") {
            PairingView(model: model)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(model: model)
        }
    }
}

/// The menu-bar glyph. Opens the main panel once at launch (the app runs as an agent, so no window
/// appears on its own).
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @State private var openedOnce = false

    var body: some View {
        Image(systemName: "link")
            .task {
                guard !openedOnce else { return }
                openedOnce = true
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
