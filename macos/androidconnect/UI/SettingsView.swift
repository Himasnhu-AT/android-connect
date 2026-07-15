//
//  SettingsView.swift
//  androidconnect
//

import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("This Mac") {
                TextField("Device name", text: $model.localDeviceName)
            }
            Section("About") {
                Text("A local-first link between this Mac and your Android phone. "
                     + "Works over your Wi-Fi only — no cloud, no account — and is end-to-end encrypted.")
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 260)
    }
}
