package com.himanshuat.androidconnect.features

import android.app.Notification
import android.app.RemoteInput
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.himanshuat.androidconnect.AndroidConnectApp
import com.himanshuat.androidconnect.protocol.NotifActionDef
import com.himanshuat.androidconnect.protocol.NotifPosted
import com.himanshuat.androidconnect.protocol.NotifRemoved

/** Lets the Mac act on a mirrored notification. Implemented by [NotificationRelayService]. */
interface NotificationSink {
    fun dismiss(key: String)
    fun act(key: String, actionId: String, reply: String?)
}

/**
 * Mirrors this phone's notifications to the paired Mac (needs the one-time "Notification access"
 * grant). Registers itself with the ConnectionManager so the Mac can reply/dismiss. See /protocol §3.
 */
class NotificationRelayService : NotificationListenerService(), NotificationSink {
    private val app get() = application as AndroidConnectApp

    override fun onListenerConnected() {
        app.connection.notificationSink = this
    }

    override fun onListenerDisconnected() {
        app.connection.notificationSink = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName) return   // don't mirror our own
        val notification = sbn.notification
        if (notification.flags and Notification.FLAG_ONGOING_EVENT != 0) return
        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        if (title.isNullOrBlank() && text.isNullOrBlank()) return

        val actions = notification.actions?.mapIndexed { index, action ->
            NotifActionDef(
                id = index.toString(),
                title = action.title?.toString().orEmpty(),
                remoteInput = action.remoteInputs?.isNotEmpty() == true,
            )
        }

        app.connection.sendNotification(
            NotifPosted(
                key = sbn.key,
                appName = appLabel(sbn.packageName),
                pkg = sbn.packageName,
                title = title,
                text = text,
                `when` = sbn.postTime,
                actions = actions,
            ),
        )
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        app.connection.sendNotification(NotifRemoved(sbn.key))
    }

    // NotificationSink — Mac-initiated actions.

    override fun dismiss(key: String) {
        cancelNotification(key)
    }

    override fun act(key: String, actionId: String, reply: String?) {
        val index = actionId.toIntOrNull() ?: return
        val sbn = activeNotifications?.firstOrNull { it.key == key } ?: return
        val action = sbn.notification.actions?.getOrNull(index) ?: return
        val remoteInputs = action.remoteInputs
        try {
            if (reply != null && remoteInputs?.isNotEmpty() == true) {
                val fill = Intent()
                val results = Bundle()
                remoteInputs.forEach { results.putCharSequence(it.resultKey, reply) }
                RemoteInput.addResultsToIntent(remoteInputs, fill, results)
                action.actionIntent?.send(this, 0, fill)
            } else {
                action.actionIntent?.send()
            }
        } catch (_: Exception) {
            // PendingIntent canceled — ignore
        }
    }

    private fun appLabel(pkg: String): String = runCatching {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    }.getOrDefault(pkg)
}
