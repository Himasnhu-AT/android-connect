//
//  MenuContent.swift
//  androidconnect
//
//  The menu-bar dropdown: a compact status + quick actions. The full UI lives in the main panel
//  (DashboardView) — this is the always-there companion.
//

import AppKit
import SwiftUI

struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if let manager = model.manager {
                statusRow(manager)
                Toggle(isOn: Binding(get: { manager.isPairing }, set: { manager.setPairing($0) })) {
                    Text("Ready to pair")
                }
                .toggleStyle(.switch)
            } else if let error = model.bootstrapError {
                Text("Couldn't start: \(error)").font(.caption).foregroundStyle(.red)
            } else {
                Text("Starting…").font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 260)
        .task { model.bootstrapIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").foregroundStyle(Color.accentColor)
            Text("AndroidConnect").font(.headline)
            Spacer()
        }
    }

    private func statusRow(_ manager: ConnectionManager) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(manager.statusText.hasPrefix("Connected") ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(manager.connectedPeerName ?? manager.statusText)
                .font(.subheadline).lineLimit(1)
            Spacer()
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open AndroidConnect", systemImage: "macwindow").frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
    }
}
