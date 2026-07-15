package com.himanshuat.androidconnect.connectivity

import com.himanshuat.androidconnect.pairing.DeviceIdentity
import java.net.Socket
import java.security.Principal
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.KeyManager
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManager
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509TrustManager

/**
 * Mutually-authenticated TLS using our Android Keystore identity, with CA validation replaced by
 * fingerprint pinning (self-signed certs). Mirrors the macOS TLSParams. See /protocol §4.
 */
class TlsTransport(
    private val identity: DeviceIdentity,
    private val accept: (fingerprint: String) -> Boolean,
) {
    private fun context(): SSLContext {
        val keyManagers = arrayOf<KeyManager>(IdentityKeyManager(identity))
        val trustManagers = arrayOf<TrustManager>(PinningTrustManager(accept))
        // "TLS" negotiates the highest supported (1.3 on API 29+, else 1.2) — safe down to minSdk 26.
        return SSLContext.getInstance("TLS").apply {
            init(keyManagers, trustManagers, SecureRandom())
        }
    }

    /** Listening socket that also requires the client to authenticate (mutual TLS). */
    fun serverSocket(port: Int = 0): SSLServerSocket =
        (context().serverSocketFactory.createServerSocket(port) as SSLServerSocket).apply {
            needClientAuth = true
        }

    /** Dials a peer and completes the TLS handshake (throws if pinning rejects it). */
    fun connect(host: String, port: Int): SSLSocket =
        (context().socketFactory.createSocket(host, port) as SSLSocket).apply {
            startHandshake()
        }
}

/** Presents our single Keystore identity for both client and server handshakes. */
private class IdentityKeyManager(private val identity: DeviceIdentity) : X509ExtendedKeyManager() {
    private val alias = "ac"

    override fun getClientAliases(keyType: String?, issuers: Array<out Principal>?) = arrayOf(alias)
    override fun chooseClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, socket: Socket?) = alias
    override fun getServerAliases(keyType: String?, issuers: Array<out Principal>?) = arrayOf(alias)
    override fun chooseServerAlias(keyType: String?, issuers: Array<out Principal>?, socket: Socket?) = alias
    override fun getCertificateChain(alias: String?): Array<X509Certificate> = identity.certificateChain
    override fun getPrivateKey(alias: String?) = identity.privateKey
}

/** Accepts a peer only if its leaf-cert fingerprint passes [accept]. */
private class PinningTrustManager(private val accept: (String) -> Boolean) : X509TrustManager {
    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String?) = verify(chain)
    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String?) = verify(chain)
    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()

    private fun verify(chain: Array<out X509Certificate>) {
        val leaf = chain.firstOrNull() ?: throw CertificateException("no peer certificate")
        val fingerprint = DeviceIdentity.fingerprintOfDer(leaf.encoded)
        if (!accept(fingerprint)) throw CertificateException("untrusted peer fingerprint")
    }
}
