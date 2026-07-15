//
//  NotificationService.swift
//  androidconnect
//
//  Shows phone notifications on the Mac (UNUserNotificationCenter) and routes Reply/Dismiss actions
//  back to the phone. See /protocol §3 (notifications).
//

import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject {
    /// Set by ConnectionManager to send actions back to the phone.
    var onDismiss: ((String) -> Void)?
    var onReply: ((_ key: String, _ actionId: String, _ text: String) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private static let category = "AC_MIRROR"

    func configure() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let reply = UNTextInputNotificationAction(
            identifier: "REPLY", title: "Reply", options: [],
            textInputButtonTitle: "Send", textInputPlaceholder: "Message")
        let dismiss = UNNotificationAction(identifier: "DISMISS", title: "Dismiss", options: [])
        let category = UNNotificationCategory(
            identifier: Self.category, actions: [reply, dismiss], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func show(_ posted: NotifPosted) {
        let content = UNMutableNotificationContent()
        if let title = posted.title, !title.isEmpty {
            content.title = title
            content.subtitle = posted.appName
        } else {
            content.title = posted.appName
        }
        content.body = posted.text ?? ""
        content.categoryIdentifier = Self.category
        var info: [String: String] = ["key": posted.key]
        if let replyId = posted.actions?.first(where: { $0.remoteInput })?.id {
            info["replyId"] = replyId
        }
        content.userInfo = info
        center.add(UNNotificationRequest(identifier: posted.key, content: content, trigger: nil))
    }

    func remove(_ key: String) {
        center.removeDeliveredNotifications(withIdentifiers: [key])
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        let info = response.notification.request.content.userInfo
        let key = (info["key"] as? String) ?? response.notification.request.identifier
        if let textResponse = response as? UNTextInputNotificationResponse,
           let replyId = info["replyId"] as? String {
            let text = textResponse.userText
            Task { @MainActor in self.onReply?(key, replyId, text) }
        } else if response.actionIdentifier == "DISMISS" {
            Task { @MainActor in self.onDismiss?(key) }
        }
        completionHandler()
    }
}
