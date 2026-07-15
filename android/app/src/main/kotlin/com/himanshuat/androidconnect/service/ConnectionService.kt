package com.himanshuat.androidconnect.service

import android.app.Notification
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import com.himanshuat.androidconnect.AndroidConnectApp
import com.himanshuat.androidconnect.R

/**
 * Owns the long-lived link to the Mac: NSD registration + the persistent TLS control connection.
 *
 * M0: minimal foreground-service shell so the manifest is valid and the process can stay alive.
 * M1 wires in [com.himanshuat.androidconnect.connectivity] (discovery, transport, pairing).
 */
class ConnectionService : LifecycleService() {

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        startForegroundCompat()
        (application as AndroidConnectApp).connection.start()
        return START_STICKY
    }

    override fun onDestroy() {
        (application as AndroidConnectApp).connection.stop()
        super.onDestroy()
    }

    private fun startForegroundCompat() {
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_CONNECTION)
            .setContentTitle("AndroidConnect")
            .setContentText("Ready to connect")
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setOngoing(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    companion object {
        const val CHANNEL_CONNECTION = "connection"
        const val CHANNEL_MIRROR = "mirror"
        private const val NOTIF_ID = 1
    }
}
