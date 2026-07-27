//
//  DashboardView.swift
//  androidconnect
//
//  The main window — a dedicated panel for status, pairing, devices, and transfers. The menu-bar
//  item (MenuContent) is a compact companion. Freeholt palette: calm, monochrome, one blue accent.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if let manager = model.manager {
                loaded(manager)
            } else if let error = model.bootstrapError {
                message("Couldn't start", error, systemImage: "exclamationmark.triangle", tint: .red)
            } else {
                message("Starting…", "Bringing up discovery and the secure link.", systemImage: "link")
            }
        }
        .frame(minWidth: 380, minHeight: 480)
        .task { model.bootstrapIfNeeded() }
    }

    // MARK: - Loaded

    private func loaded(_ manager: ConnectionManager) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                hero(manager)
                if let call = manager.callService.current { CallCard(call: call, manager: manager) }
                if manager.connectedPeerName == nil { pairing(manager) }   // hide QR/pairing once connected
                devices(manager)
                transfers(manager)
            }
            .padding(18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach { manager.sendFile($0) }
            return !urls.isEmpty
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer(manager) }
    }

    // MARK: - Hero

    private func hero(_ manager: ConnectionManager) -> some View {
        let connected = manager.connectedPeerName != nil
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(connected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                Image(systemName: connected ? "iphone.gen3" : "iphone.slash")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(connected ? Color.accentColor : .secondary)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(manager.connectedPeerName ?? "No phone connected")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle()
                        .fill(manager.statusText.hasPrefix("Connected") ? Color.green : .secondary)
                        .frame(width: 7, height: 7)
                    Text(manager.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Pairing

    private func pairing(_ manager: ConnectionManager) -> some View {
        Card(title: "Pairing", systemImage: "qrcode") {
            Toggle(isOn: Binding(get: { manager.isPairing }, set: { manager.setPairing($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ready to pair").font(.body)
                    Text(manager.isPairing ? "Scan the QR on your phone, or tap this Mac in its list"
                                           : "Turn on to add a new phone")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Button {
                openWindow(id: "pair")
            } label: {
                Label("Show QR code…", systemImage: "qrcode").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
    }

    // MARK: - Devices

    private func devices(_ manager: ConnectionManager) -> some View {
        let nearby = manager.discovered.filter { d in !manager.pairedPeers.contains { $0.id == d.id } }
        return Card(title: "Devices", systemImage: "laptopcomputer.and.iphone") {
            if manager.pairedPeers.isEmpty && nearby.isEmpty {
                EmptyLine("No devices yet — turn on “Ready to pair”.")
            }
            ForEach(manager.pairedPeers) { peer in
                DeviceRow(
                    name: peer.name,
                    detail: manager.connectedPeerName == peer.name ? "Connected" : "Paired",
                    connected: manager.connectedPeerName == peer.name
                ) {
                    Button(role: .destructive) { manager.unpair(peer) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless).help("Unpair")
                }
            }
            if !nearby.isEmpty {
                if !manager.pairedPeers.isEmpty { Divider() }
                Text("Nearby").font(.caption).foregroundStyle(.secondary)
                ForEach(nearby) { peer in
                    DeviceRow(name: peer.name, detail: "Nearby", connected: false) {
                        Button("Pair") { manager.pair(with: peer) }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Transfers

    private func transfers(_ manager: ConnectionManager) -> some View {
        let items = Array(manager.fileTransfer.transfers.suffix(6).reversed())
        return Card(title: "Transfers", systemImage: "arrow.up.arrow.down") {
            if items.isEmpty {
                EmptyLine("Drop a file on this window, or click Send file.")
            }
            ForEach(items) { t in TransferRow(transfer: t) }
            Button {
                pickAndSend(manager)
            } label: {
                Label("Send file…", systemImage: "paperplane").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
    }

    // MARK: - Footer

    private func footer(_ manager: ConnectionManager) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "laptopcomputer").foregroundStyle(.secondary)
            Text(manager.identity.deviceName).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button { openSettings() } label: { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Settings")
            Button("Quit") { NSApplication.shared.terminate(nil) }.controlSize(.small)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.bar)
    }

    private func message(_ title: String, _ subtitle: String, systemImage: String, tint: Color = .secondary) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 34)).foregroundStyle(tint)
            Text(title).font(.headline)
            Text(subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickAndSend(_ manager: ConnectionManager) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { panel.urls.forEach { manager.sendFile($0) } }
    }
}

// MARK: - Reusable pieces

private struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

private struct DeviceRow<Trailing: View>: View {
    let name: String
    let detail: String
    let connected: Bool
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone.gen3").foregroundStyle(connected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.body)
                Text(detail).font(.caption).foregroundStyle(connected ? .green : .secondary)
            }
            Spacer()
            trailing
        }
    }
}

private struct TransferRow: View {
    let transfer: FileTransferService.Transfer

    private var openable: Bool { transfer.done && !transfer.failed && transfer.localURL != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: transfer.incoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundStyle(transfer.failed ? .red : transfer.done ? .green : Color.accentColor)
                Text(transfer.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(transfer.failed ? "Failed" : openable ? "Open" : transfer.done ? "Done" : "\(Int(transfer.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(transfer.failed ? .red : openable ? Color.accentColor : .secondary)
            }
            if !transfer.done && !transfer.failed {
                ProgressView(value: transfer.progress).controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if openable, let url = transfer.localURL { NSWorkspace.shared.open(url) }
        }
        .help(openable ? "Open \(transfer.name)" : "")
    }
}

private struct EmptyLine: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
    }
}

private struct CallCard: View {
    let call: CallService.Call
    let manager: ConnectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "phone.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(call.displayName).font(.headline)
                    Text(call.isRinging ? "Incoming call" : "In call — audio on your phone")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                if call.isRinging {
                    Button { manager.callService.answer() } label: { Label("Answer", systemImage: "phone.fill") }.tint(.green)
                    Button { manager.callService.decline() } label: { Label("Decline", systemImage: "phone.down.fill") }.tint(.red)
                } else {
                    Button { manager.callService.end() } label: { Label("End", systemImage: "phone.down.fill") }.tint(.red)
                }
            }
            .buttonStyle(.borderedProminent).controlSize(.regular)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.30), lineWidth: 1))
    }
}

private extension View {
    func cardBackground() -> some View {
        background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}
