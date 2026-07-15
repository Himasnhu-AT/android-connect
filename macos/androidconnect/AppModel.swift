//
//  AppModel.swift
//  androidconnect
//
//  Root observable state. Owns the ConnectionManager, created lazily on first appearance so the
//  identity/keychain work and network start happen once at launch.
//

import Foundation
import Observation

@Observable
@MainActor
final class AppModel {
    /// This Mac's advertised name.
    var localDeviceName: String = Host.current().localizedName ?? "This Mac"

    private(set) var manager: ConnectionManager?
    private(set) var bootstrapError: String?
    private var bootstrapped = false

    func bootstrapIfNeeded() {
        guard !bootstrapped else { return }
        bootstrapped = true
        do {
            let identity = try DeviceIdentity.loadOrCreate(deviceName: localDeviceName)
            let manager = ConnectionManager(identity: identity)
            manager.start()
            self.manager = manager
        } catch {
            bootstrapError = "\(error)"
        }
    }
}
