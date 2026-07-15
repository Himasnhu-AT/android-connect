package com.himanshuat.androidconnect.protocol

import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/**
 * One transport frame: `[uint32 BE length][uint8 type][payload]`, where `length` counts
 * `type + payload`. See /protocol/PROTOCOL.md §2. Big-endian, max 1 MiB.
 */
data class Frame(val type: Int, val payload: ByteArray) {
    // data class with a ByteArray needs structural equals/hashCode (for tests & sets).
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is Frame) return false
        return type == other.type && payload.contentEquals(other.payload)
    }

    override fun hashCode(): Int = 31 * type + payload.contentHashCode()
}

object Framing {
    const val TYPE_JSON = 0x00
    const val TYPE_BINARY = 0x01

    const val MAX_FRAME = 1 shl 20            // 1 MiB hard cap on a single frame
    const val MAX_CHUNK = 64 * 1024           // binary chunks are capped so control msgs interleave
    const val TRANSFER_ID_LEN = 16            // bytes prefixed to a binary chunk payload

    /** Writes one frame. Caller is responsible for the payload being within [MAX_FRAME]. */
    @Throws(IOException::class)
    fun write(out: OutputStream, type: Int, payload: ByteArray) {
        val len = payload.size + 1
        require(len in 1..MAX_FRAME) { "frame length out of range: $len" }
        out.write((len ushr 24) and 0xFF)
        out.write((len ushr 16) and 0xFF)
        out.write((len ushr 8) and 0xFF)
        out.write(len and 0xFF)
        out.write(type and 0xFF)
        out.write(payload)
        out.flush()
    }

    /** Reads one frame, or returns null at a clean end-of-stream. Throws on a truncated/oversized frame. */
    @Throws(IOException::class)
    fun read(input: InputStream): Frame? {
        val b0 = input.read()
        if (b0 == -1) return null // clean EOF between frames
        val b1 = input.read(); val b2 = input.read(); val b3 = input.read()
        if (b1 or b2 or b3 == -1) throw EOFException("truncated frame length")
        val len = (b0 shl 24) or (b1 shl 16) or (b2 shl 8) or b3
        if (len < 1 || len > MAX_FRAME) throw IOException("illegal frame length: $len")
        val type = input.read()
        if (type == -1) throw EOFException("truncated frame type")
        val payload = ByteArray(len - 1)
        readFully(input, payload)
        return Frame(type, payload)
    }

    /** Builds a binary-chunk payload: `[16-byte transferId][data]`. */
    fun binaryPayload(transferId: ByteArray, data: ByteArray): ByteArray {
        require(transferId.size == TRANSFER_ID_LEN) { "transferId must be $TRANSFER_ID_LEN bytes" }
        return transferId + data
    }

    /** Splits a binary-chunk payload back into `(transferId, data)`. */
    fun splitBinaryPayload(payload: ByteArray): Pair<ByteArray, ByteArray> {
        require(payload.size >= TRANSFER_ID_LEN) { "binary payload too short" }
        return payload.copyOfRange(0, TRANSFER_ID_LEN) to payload.copyOfRange(TRANSFER_ID_LEN, payload.size)
    }

    private fun readFully(input: InputStream, buf: ByteArray) {
        var off = 0
        while (off < buf.size) {
            val n = input.read(buf, off, buf.size - off)
            if (n == -1) throw EOFException("truncated frame payload: got $off of ${buf.size}")
            off += n
        }
    }
}
