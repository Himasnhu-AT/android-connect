//
//  ClipboardService.swift
//  androidconnect
//
//  Watches NSPasteboard (no change notifications exist, so we poll changeCount) and applies remote
//  clipboards, suppressing the echo of anything we just set ourselves. See /protocol §3 (clipboard).
//

import AppKit

@MainActor
final class ClipboardService {
    /// Fires when the *local* clipboard changes to new text (not something we just applied).
    var onLocalChange: ((String) -> Void)?

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var lastText: String?
    private var timer: Timer?

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Apply a clipboard received from the peer (without re-broadcasting it).
    func apply(_ text: String) {
        guard text != lastText else { return }
        lastText = text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        guard text != lastText else { return } // we just applied this
        lastText = text
        onLocalChange?(text)
    }
}
