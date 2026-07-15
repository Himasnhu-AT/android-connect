//
//  PairingView.swift
//  androidconnect
//
//  Pairing window: shows a QR the phone scans, and puts the Mac in pairing mode while open.
//

import SwiftUI

struct PairingView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Pair a phone")
                .font(.headline)
            Text("Open AndroidConnect on your phone and scan this code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            qr

            Text("On the same Wi-Fi you can also just tap this Mac in the phone's list.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 320, height: 400)
        .onAppear { model.manager?.setPairing(true) }
        .onDisappear { model.manager?.setPairing(false) }
    }

    @ViewBuilder
    private var qr: some View {
        if let payload = model.manager?.pairingPayload(),
           let image = QRCode.image(from: payload) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 220, height: 220)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(spacing: 8) {
                ProgressView()
                Text("Getting ready…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, height: 220)
        }
    }
}
