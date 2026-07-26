//
//  MenuContent.swift
//  androidconnect
//
//  The menu-bar dropdown: status, paired phones, and nearby phones to pair with.
//

import AppKit
import SwiftUI

struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .task { model.bootstrapIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if let manager = model.manager {
            if let call = manager.callService.current {
                callBanner(call, manager)
            }
            statusRow(manager.statusText)
            pairingToggle(manager)
            pairedSection(manager)
            discoveredSection(manager)
            transfersSection(manager)
            HStack {
                Button {
                    openWindow(id: "pair")
                } label: {
                    Label("Pair…", systemImage: "qrcode")
                }
                Spacer()
                Button {
                    pickAndSend(manager)
                } label: {
                    Label("Send file…", systemImage: "paperplane")
                }
            }
            .buttonStyle(.borderless)
        } else if let error = model.bootstrapError {
            Text("Couldn't start: \(error)")
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Text("Starting…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(Color.accentColor)
            Text("AndroidConnect")
                .font(.headline)
            Spacer()
        }
    }

    private func pairingToggle(_ manager: ConnectionManager) -> some View {
        Toggle(isOn: Binding(get: { manager.isPairing }, set: { manager.setPairing($0) })) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Ready to pair").font(.subheadline)
                Text(manager.isPairing
                     ? "Accepting a new phone — scan the QR or tap this Mac on the phone"
                     : "Turn on to pair a new phone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(text.hasPrefix("Connected") ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    @ViewBuilder
    private func pairedSection(_ manager: ConnectionManager) -> some View {
        if !manager.pairedPeers.isEmpty {
            Text("Paired")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(manager.pairedPeers) { peer in
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                    Text(peer.name)
                    Spacer()
                    Button {
                        manager.unpair(peer)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Unpair")
                }
            }
        }
    }

    @ViewBuilder
    private func discoveredSection(_ manager: ConnectionManager) -> some View {
        let unpaired = manager.discovered.filter { discovered in
            !manager.pairedPeers.contains { $0.id == discovered.id }
        }
        if !unpaired.isEmpty {
            Text("Nearby")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(unpaired) { peer in
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                    Text(peer.name)
                    Spacer()
                    Button("Pair") { manager.pair(with: peer) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private func transfersSection(_ manager: ConnectionManager) -> some View {
        let items = Array(manager.fileTransfer.transfers.suffix(4))
        if !items.isEmpty {
            Text("Transfers")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(items) { transfer in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: transfer.incoming ? "arrow.down.circle" : "arrow.up.circle")
                        Text(transfer.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(transfer.failed ? "Failed"
                             : transfer.done ? "Done"
                             : "\(Int(transfer.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(transfer.failed ? .red : .secondary)
                    }
                    if !transfer.done, !transfer.failed {
                        ProgressView(value: transfer.progress)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func callBanner(_ call: CallService.Call, _ manager: ConnectionManager) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "phone.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(call.displayName)
                        .font(.headline)
                    Text(call.isRinging ? "Incoming call" : "In call — audio on your phone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                if call.isRinging {
                    Button { manager.callService.answer() } label: {
                        Label("Answer", systemImage: "phone.fill")
                    }
                    .tint(.green)
                    Button { manager.callService.decline() } label: {
                        Label("Decline", systemImage: "phone.down.fill")
                    }
                    .tint(.red)
                } else {
                    Button { manager.callService.end() } label: {
                        Label("End", systemImage: "phone.down.fill")
                    }
                    .tint(.red)
                }
            }
            .buttonStyle(.bordered)
            Divider()
        }
    }

    private func pickAndSend(_ manager: ConnectionManager) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            manager.sendFile(url)
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { openSettings() }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
