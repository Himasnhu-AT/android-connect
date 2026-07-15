package com.himanshuat.androidconnect.pairing

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.util.Date
import javax.security.auth.x500.X500Principal

/**
 * This phone's persistent TLS identity: a non-exportable P-256 key in the Android Keystore plus the
 * self-signed certificate the Keystore mints for it. The SHA-256 of the cert is the pinned
 * fingerprint (see /protocol §4). The private key never leaves the Keystore; TLS signs through it.
 */
class DeviceIdentity private constructor(
    val privateKey: PrivateKey,
    val certificate: X509Certificate,
    val certificateChain: Array<X509Certificate>,
    val fingerprint: String,
    val deviceId: String,
) {
    companion object {
        private const val ALIAS = "androidconnect.identity"
        private const val KEYSTORE = "AndroidKeyStore"

        fun loadOrCreate(deviceId: String, commonName: String): DeviceIdentity {
            val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            val cert = ks.getCertificate(ALIAS) as? X509Certificate
            val key = ks.getKey(ALIAS, null) as? PrivateKey
            return if (cert != null && key != null) {
                build(key, cert, deviceId)
            } else {
                generate(deviceId, commonName)
            }
        }

        private fun generate(deviceId: String, commonName: String): DeviceIdentity {
            val now = System.currentTimeMillis()
            val spec = KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
            )
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setCertificateSubject(X500Principal("CN=$commonName"))
                .setCertificateSerialNumber(BigInteger.valueOf(now))
                .setCertificateNotBefore(Date(now - 86_400_000L))
                .setCertificateNotAfter(Date(now + 3_650L * 86_400_000L))
                .build()

            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE).apply {
                initialize(spec)
                generateKeyPair()
            }

            val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            val cert = ks.getCertificate(ALIAS) as X509Certificate
            val key = ks.getKey(ALIAS, null) as PrivateKey
            return build(key, cert, deviceId)
        }

        private fun build(key: PrivateKey, cert: X509Certificate, deviceId: String) =
            DeviceIdentity(key, cert, arrayOf(cert), fingerprintOf(cert), deviceId)

        fun fingerprintOf(cert: X509Certificate): String = fingerprintOfDer(cert.encoded)

        fun fingerprintOfDer(der: ByteArray): String =
            MessageDigest.getInstance("SHA-256").digest(der)
                .joinToString("") { "%02x".format(it) }
    }
}
