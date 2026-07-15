package com.himanshuat.androidconnect.features

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context

/**
 * Bridges the system clipboard. Android 10+ only lets the FOREGROUND app (or the default IME)
 * read or write the clipboard — so local-change events and applying remote clips are effective
 * mainly while the app is on screen. See /protocol §3 and the README's platform limits.
 */
class ClipboardHandler(context: Context) {
    private val appContext = context.applicationContext
    private val clipboard = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private var lastText: String? = null

    var onLocalChange: ((String) -> Unit)? = null

    private val listener = ClipboardManager.OnPrimaryClipChangedListener {
        val text = currentText() ?: return@OnPrimaryClipChangedListener
        if (text == lastText) return@OnPrimaryClipChangedListener
        lastText = text
        onLocalChange?.invoke(text)
    }

    fun start() = clipboard.addPrimaryClipChangedListener(listener)

    fun stop() = clipboard.removePrimaryClipChangedListener(listener)

    /** Apply a clipboard received from the peer (without re-broadcasting it). */
    fun apply(text: String) {
        if (text == lastText) return
        lastText = text
        runCatching { clipboard.setPrimaryClip(ClipData.newPlainText("AndroidConnect", text)) }
    }

    private fun currentText(): String? {
        val clip = clipboard.primaryClip ?: return null
        if (clip.itemCount == 0) return null
        return clip.getItemAt(0).coerceToText(appContext).toString().takeIf { it.isNotEmpty() }
    }
}
