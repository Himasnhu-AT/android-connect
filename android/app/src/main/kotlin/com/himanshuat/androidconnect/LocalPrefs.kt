package com.himanshuat.androidconnect

import android.content.Context
import android.os.Build
import java.util.UUID

/** Stable per-install device id + editable device name. */
class LocalPrefs(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("local", Context.MODE_PRIVATE)

    val deviceId: String
        get() = prefs.getString(KEY_ID, null) ?: UUID.randomUUID().toString().also {
            prefs.edit().putString(KEY_ID, it).apply()
        }

    var deviceName: String
        get() = prefs.getString(KEY_NAME, null) ?: defaultName()
        set(value) { prefs.edit().putString(KEY_NAME, value).apply() }

    /** Whether to mirror this phone's notifications to the Mac (user-toggleable). */
    var notificationsEnabled: Boolean
        get() = prefs.getBoolean(KEY_NOTIF, false)
        set(value) { prefs.edit().putBoolean(KEY_NOTIF, value).apply() }

    /** Whether to share call state with the Mac (user-toggleable). */
    var callsEnabled: Boolean
        get() = prefs.getBoolean(KEY_CALLS, false)
        set(value) { prefs.edit().putBoolean(KEY_CALLS, value).apply() }

    private fun defaultName(): String {
        val model = Build.MODEL?.takeIf { it.isNotBlank() } ?: "Android"
        return model.replaceFirstChar { it.uppercase() }
    }

    private companion object {
        const val KEY_ID = "deviceId"
        const val KEY_NAME = "deviceName"
        const val KEY_NOTIF = "notificationsEnabled"
        const val KEY_CALLS = "callsEnabled"
    }
}
