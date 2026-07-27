package com.himanshuat.androidconnect.features

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.OpenableColumns
import com.himanshuat.androidconnect.protocol.ControlMessage
import com.himanshuat.androidconnect.protocol.FileAccept
import com.himanshuat.androidconnect.protocol.FileComplete
import com.himanshuat.androidconnect.protocol.FileOffer
import com.himanshuat.androidconnect.protocol.FileReject
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.security.SecureRandom
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * File/photo transfer over the binary-chunk frame (type 0x01) + fileOffer/Accept/Complete messages.
 * transferId = 16 random bytes as 32-char hex in control messages, raw bytes in binary frames.
 * Received files land in the app's external Downloads dir (no permission needed). See /protocol §3.
 */
class FileTransferHandler(context: Context, private val scope: CoroutineScope) {
    data class Transfer(
        val id: String,
        val name: String,
        val size: Long,
        val transferred: Long,
        val incoming: Boolean,
        val done: Boolean,
        val failed: Boolean,
        /** Incoming: absolute path of the saved file. Outgoing: the source content-URI string. */
        val localPath: String? = null,
    ) {
        val progress: Float
            get() = when {
                done -> 1f
                size > 0 -> (transferred.toFloat() / size).coerceIn(0f, 1f)
                else -> 0f
            }
    }

    private val appContext = context.applicationContext
    private val resolver = appContext.contentResolver

    private val _transfers = MutableStateFlow<List<Transfer>>(emptyList())
    val transfers: StateFlow<List<Transfer>> = _transfers.asStateFlow()

    var onSend: ((ControlMessage) -> Unit)? = null
    var onSendBinary: ((ByteArray, ByteArray) -> Unit)? = null

    private val incoming = HashMap<String, OutputStream>()
    private val pendingOutgoing = HashMap<String, Uri>()
    private val lock = Any()

    // MARK: sending

    fun sendFile(uri: Uri) {
        val (name, size) = queryMeta(uri)
        val idHex = newIdHex()
        synchronized(lock) { pendingOutgoing[idHex] = uri }
        addTransfer(Transfer(idHex, name, size, 0, incoming = false, done = false, failed = false, localPath = uri.toString()))
        onSend?.invoke(FileOffer(transferId = idHex, name = name, size = size, mime = resolver.getType(uri)))
    }

    fun handleAccept(idHex: String) {
        val uri = synchronized(lock) { pendingOutgoing.remove(idHex) } ?: return
        stream(idHex, uri)
    }

    fun handleReject(idHex: String) {
        synchronized(lock) { pendingOutgoing.remove(idHex) }
        markFailed(idHex)
    }

    // MARK: receiving

    fun handleOffer(offer: FileOffer) {
        val dir = appContext.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        val file = File(dir, sanitize(offer.name))
        val out = runCatching { FileOutputStream(file) }.getOrNull()
        if (out == null) {
            onSend?.invoke(FileReject(transferId = offer.transferId, reason = "cannot write"))
            return
        }
        synchronized(lock) { incoming[offer.transferId] = out }
        addTransfer(Transfer(offer.transferId, offer.name, offer.size, 0, incoming = true, done = false, failed = false, localPath = file.absolutePath))
        onSend?.invoke(FileAccept(transferId = offer.transferId))
    }

    fun handleChunk(transferId: ByteArray, data: ByteArray) {
        val idHex = hex(transferId)
        val out = synchronized(lock) { incoming[idHex] } ?: return
        runCatching {
            out.write(data)
            bump(idHex, data.size)
        }.onFailure { markFailed(idHex) }
    }

    fun handleComplete(idHex: String) {
        val out = synchronized(lock) { incoming.remove(idHex) }
        out?.let { runCatching { it.flush(); it.close() } }
        markDone(idHex)
    }

    // MARK: streaming

    private fun stream(idHex: String, uri: Uri) {
        val idBytes = fromHex(idHex)
        if (idBytes == null) {
            markFailed(idHex)
            return
        }
        scope.launch(Dispatchers.IO) {
            try {
                resolver.openInputStream(uri)!!.use { input ->
                    val buffer = ByteArray(CHUNK)
                    while (true) {
                        val n = input.read(buffer)
                        if (n == -1) break
                        onSendBinary?.invoke(idBytes, buffer.copyOf(n))
                        bump(idHex, n)
                    }
                }
                onSend?.invoke(FileComplete(transferId = idHex))
                markDone(idHex)
            } catch (_: Exception) {
                markFailed(idHex)
            }
        }
    }

    // MARK: bookkeeping

    private fun addTransfer(t: Transfer) = synchronized(lock) { _transfers.value = _transfers.value + t }

    private fun update(idHex: String, f: (Transfer) -> Transfer) = synchronized(lock) {
        _transfers.value = _transfers.value.map { if (it.id == idHex) f(it) else it }
    }

    private fun bump(idHex: String, n: Int) = update(idHex) { it.copy(transferred = it.transferred + n) }
    private fun markDone(idHex: String) = update(idHex) { it.copy(done = true) }
    private fun markFailed(idHex: String) = update(idHex) { it.copy(failed = true) }

    // MARK: helpers

    private fun queryMeta(uri: Uri): Pair<String, Long> {
        var name = "file"
        var size = 0L
        resolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val ni = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val si = c.getColumnIndex(OpenableColumns.SIZE)
                if (ni >= 0) c.getString(ni)?.let { name = it }
                if (si >= 0 && !c.isNull(si)) size = c.getLong(si)
            }
        }
        return name to size
    }

    private fun newIdHex(): String = hex(ByteArray(16).also { SecureRandom().nextBytes(it) })

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }

    private fun fromHex(s: String): ByteArray? = runCatching {
        ByteArray(s.length / 2) { ((s[it * 2].digitToInt(16) shl 4) or s[it * 2 + 1].digitToInt(16)).toByte() }
    }.getOrNull()

    private fun sanitize(name: String): String = name.replace(Regex("[/\\\\]"), "_").ifBlank { "file" }

    private companion object {
        const val CHUNK = 64 * 1024
    }
}
