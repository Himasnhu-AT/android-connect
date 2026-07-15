package com.himanshuat.androidconnect.features

import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import com.himanshuat.androidconnect.protocol.CallState

/**
 * Mirrors phone-call state to the Mac and answers/declines/ends on the Mac's behalf via TelecomManager.
 * Call audio can't leave the phone over LAN, so we only mirror state + control the call. See /protocol §3.
 *
 * Uses PhoneStateListener (deprecated but works down to minSdk 26 and still delivers the number with
 * READ_CALL_LOG, which TelephonyCallback on API 31+ does not).
 */
class CallHandler(context: Context) {
    private val appContext = context.applicationContext
    private val telephony = appContext.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
    private val telecom = appContext.getSystemService(Context.TELECOM_SERVICE) as TelecomManager

    var onCallState: ((CallState) -> Unit)? = null

    private var lastState = TelephonyManager.CALL_STATE_IDLE
    private var currentCallId: String? = null

    @Suppress("DEPRECATION")
    private val listener = object : PhoneStateListener() {
        override fun onCallStateChanged(state: Int, phoneNumber: String?) = handle(state, phoneNumber)
    }

    @Suppress("DEPRECATION")
    fun start() {
        runCatching { telephony.listen(listener, PhoneStateListener.LISTEN_CALL_STATE) }
    }

    @Suppress("DEPRECATION")
    fun stop() {
        runCatching { telephony.listen(listener, PhoneStateListener.LISTEN_NONE) }
    }

    fun action(action: String) {
        when (action) {
            "answer" -> runCatching { telecom.acceptRingingCall() }
            "decline", "end" ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) runCatching { telecom.endCall() }
            else -> Unit // mute/unmute need an InCallService — not in v1
        }
    }

    private fun handle(state: Int, number: String?) {
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                val id = number?.takeIf { it.isNotEmpty() } ?: "call"
                currentCallId = id
                onCallState?.invoke(
                    CallState(
                        callId = id, state = "ringing", direction = "incoming",
                        number = number, contactName = lookupContact(number),
                    ),
                )
            }

            TelephonyManager.CALL_STATE_OFFHOOK -> {
                val id = currentCallId ?: "call"
                currentCallId = id
                onCallState?.invoke(
                    CallState(
                        callId = id, state = "active",
                        direction = if (lastState == TelephonyManager.CALL_STATE_RINGING) "incoming" else "outgoing",
                    ),
                )
            }

            TelephonyManager.CALL_STATE_IDLE -> {
                onCallState?.invoke(
                    CallState(callId = currentCallId ?: "call", state = "disconnected", direction = "incoming"),
                )
                currentCallId = null
            }
        }
        lastState = state
    }

    private fun lookupContact(number: String?): String? {
        if (number.isNullOrEmpty()) return null
        val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
        return runCatching {
            appContext.contentResolver.query(
                uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null,
            )?.use { if (it.moveToFirst()) it.getString(0) else null }
        }.getOrNull()
    }
}
