package com.himanshuat.androidconnect

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import com.himanshuat.androidconnect.connectivity.ConnectionManager
import com.himanshuat.androidconnect.service.ConnectionService

class AndroidConnectApp : Application() {
    /** App-wide connection layer; created on first access, started by [ConnectionService]. */
    val connection: ConnectionManager by lazy { ConnectionManager(this) }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        val nm = getSystemService(NotificationManager::class.java)

        // Low-importance, ongoing channel for the connection foreground service.
        nm.createNotificationChannel(
            NotificationChannel(
                ConnectionService.CHANNEL_CONNECTION,
                getString(R.string.connection_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = getString(R.string.connection_channel_desc)
                setShowBadge(false)
            },
        )

        // Default-importance channel used to surface mirrored notifications (M4).
        nm.createNotificationChannel(
            NotificationChannel(
                ConnectionService.CHANNEL_MIRROR,
                getString(R.string.mirror_channel_name),
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }
}
