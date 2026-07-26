package com.himanshuat.androidconnect.connectivity

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log

/** A device found on the network, resolved to a reachable host/port. */
data class DiscoveredPeer(
    val id: String,
    val name: String,
    val plat: String,
    val fingerprint: String,
    val host: String,
    val port: Int,
)

/**
 * mDNS/Bonjour advertise (register) + browse (discover) for `_androidconnect._tcp` via NsdManager.
 * TXT carries id/name/plat/fp/pv (see /protocol §1). Mirrors the macOS Discovery.
 */
class NsdDiscovery(context: Context) {
    private val nsd = context.applicationContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private val peers = LinkedHashMap<String, DiscoveredPeer>()

    fun register(serviceName: String, port: Int, txt: Map<String, String>) {
        val info = NsdServiceInfo().apply {
            this.serviceName = serviceName
            serviceType = SERVICE_TYPE
            this.port = port
            txt.forEach { (key, value) -> setAttribute(key, value) }
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                Log.i("ACDebug", "NSD registered as '${info.serviceName}' port=$port")
            }
            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.e("ACDebug", "NSD registration FAILED errorCode=$errorCode (0=INTERNAL,1=ALREADY_ACTIVE,2=MAX_LIMIT)")
            }
            override fun onServiceUnregistered(info: NsdServiceInfo) {}
            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {}
        }
        registrationListener = listener
        Log.i("ACDebug", "NSD registering '$serviceName' type=$SERVICE_TYPE port=$port")
        nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    fun discover(onChange: (List<DiscoveredPeer>) -> Unit) {
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceType.contains("androidconnect")) resolve(service, onChange)
            }
            override fun onServiceLost(service: NsdServiceInfo) {
                synchronized(peers) { peers.remove(service.serviceName) }
                onChange(snapshot())
            }
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }
        discoveryListener = listener
        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    private fun resolve(service: NsdServiceInfo, onChange: (List<DiscoveredPeer>) -> Unit) {
        val resolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {}
            override fun onServiceResolved(info: NsdServiceInfo) {
                @Suppress("DEPRECATION")
                val host = info.host?.hostAddress ?: return
                fun attr(key: String) = info.attributes[key]?.toString(Charsets.UTF_8).orEmpty()
                val peer = DiscoveredPeer(
                    id = attr("id").ifEmpty { info.serviceName },
                    name = attr("name").ifEmpty { info.serviceName },
                    plat = attr("plat"),
                    fingerprint = attr("fp"),
                    host = host,
                    port = info.port,
                )
                synchronized(peers) { peers[info.serviceName] = peer }
                onChange(snapshot())
            }
        }
        @Suppress("DEPRECATION")
        runCatching { nsd.resolveService(service, resolveListener) }
    }

    private fun snapshot(): List<DiscoveredPeer> = synchronized(peers) { peers.values.toList() }

    fun stop() {
        registrationListener?.let { runCatching { nsd.unregisterService(it) } }
        discoveryListener?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        registrationListener = null
        discoveryListener = null
        synchronized(peers) { peers.clear() }
    }

    private companion object {
        const val SERVICE_TYPE = "_androidconnect._tcp"
    }
}
