//
//  androidconnectApp.swift
//  androidconnect
//
//  Local-first link between this Mac and an Android phone. LAN only, end-to-end encrypted.
//

import SwiftUI

@main
struct androidconnectApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // Menu-bar utility is the primary surface (the app runs as an agent — see LSUIElement).
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: "link")
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
