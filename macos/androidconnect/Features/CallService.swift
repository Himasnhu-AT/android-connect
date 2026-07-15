//
//  CallService.swift
//  androidconnect
//
//  Holds the current phone-call state (mirrored from the phone) and sends answer/decline/end back.
//  Call audio stays on the phone — over LAN we can only mirror state and control the call. §3.
//

import Foundation
import Observation

@MainActor
@Observable
final class CallService {
    struct Call: Equatable, Identifiable {
        var id: String
        var state: String       // ringing | active | dialing | disconnected
        var direction: String   // incoming | outgoing
        var number: String?
        var contactName: String?

        var displayName: String { contactName ?? number ?? "Unknown" }
        var isRinging: Bool { state == "ringing" }
    }

    private(set) var current: Call?

    /// Set by ConnectionManager to send a callAction back to the phone.
    var onAction: ((_ callId: String, _ action: String) -> Void)?

    func update(_ state: CallState) {
        if state.state == "disconnected" {
            current = nil
        } else {
            current = Call(
                id: state.callId, state: state.state, direction: state.direction,
                number: state.number, contactName: state.contactName)
        }
    }

    func answer() { act("answer") }
    func decline() { act("decline") }
    func end() { act("end") }

    private func act(_ action: String) {
        guard let call = current else { return }
        onAction?(call.id, action)
    }
}
