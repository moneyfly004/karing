package io.nebula.vpn_service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import com.cyenx.clashmi.core.clashmicore.Clashmicore
import com.cyenx.clashmi.core.clashmicore.SocketProtector
import java.io.File
import java.net.NetworkInterface
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray
import org.json.JSONObject

class VpnServiceImpl : VpnService() {
    private val stopping = AtomicBoolean(false)
    private var tunFd: Int = -1
    private var tunPfd: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopCore("stop action")
            ACTION_START, null -> startCore()
            else -> Log.w(TAG, "unknown action=${intent.action}")
        }
        return Service.START_STICKY
    }

    override fun onDestroy() {
        stopCore("service destroy")
        super.onDestroy()
    }

    override fun onRevoke() {
        Log.w(TAG, "vpn revoked")
        stopCore("vpn revoked")
        super.onRevoke()
    }

    private fun startCore() {
        if (worker?.isAlive == true) {
            Log.i(TAG, "core start ignored: worker already alive")
            VpnServiceRuntime.completeStart(VpnServiceRuntime.doneResult())
            return
        }
        stopping.set(false)
        startForegroundService()
        worker = Thread({
            val config = VpnServiceRuntime.preparedConfig ?: restorePreparedConfig()
            if (config == null) {
                failStart("missing prepared config")
                return@Thread
            }
            try {
                Log.i(TAG, "core starting config=${config.corePath} patch=${config.corePathPatch} finalPatch=${config.corePathPatchFinal}")
                updateState("connecting")
                clearErrorFile(config)
                installSocketProtector()
                updateAndroidNetworkInfo("core start")
                registerNetworkCallback()
                val fd = openTun(config)
                tunFd = fd
                Log.i(TAG, "handing tun fd to core fd=$fd")
                tunFd = -1
                Clashmicore.start(
                    config.corePath,
                    config.corePathPatch,
                    config.corePathPatchFinal,
                    config.baseDir,
                    fd.toLong(),
                    config.externalController,
                    config.secret,
                )
                Log.i(TAG, "core started fd=$fd controller=${config.externalController} tun=${Clashmicore.tunInfo()}")
                updateState("connected")
                VpnServiceRuntime.completeStart(VpnServiceRuntime.doneResult())
            } catch (error: Throwable) {
                val message = error.message ?: error.toString()
                Log.e(TAG, "core start failed: $message", error)
                writeErrorFile(config, message)
                unregisterNetworkCallback()
                closeTunFd()
                Clashmicore.stop()
                updateState("disconnected")
                VpnServiceRuntime.completeStart(VpnServiceRuntime.errorResult(message))
                stopSelf()
            }
        }, "VpnServiceVpnCore")
        worker?.start()
    }

    private fun stopCore(reason: String) {
        if (worker?.isAlive != true &&
            tunFd < 0 &&
            tunPfd == null &&
            VpnServiceRuntime.currentState == "disconnected"
        ) {
            Log.i(TAG, "core stop ignored: already disconnected reason=$reason")
            stopSelf()
            return
        }
        if (!stopping.compareAndSet(false, true)) {
            return
        }
        Log.i(TAG, "core stopping reason=$reason")
        updateState("disconnecting")
        unregisterNetworkCallback()
        try {
            Clashmicore.stop()
        } catch (error: Throwable) {
            Log.w(TAG, "core stop failed: ${error.message}", error)
        }
        closeTunFd()
        updateState("disconnected")
        stopForegroundCompat()
        stopSelf()
    }

    private fun openTun(config: PreparedVpnConfig): Int {
        val builder = Builder()
            .setSession(config.name)
            .setMtu(DEFAULT_MTU)
            .addAddress(TUN_IPV4_ADDRESS, TUN_IPV4_PREFIX)
            .addRoute("0.0.0.0", 0)
            .addDnsServer(TUN_DNS_SERVER)

        val enableIPv6Route = resolveEffectiveIPv6(config)
        if (enableIPv6Route) {
            builder
                .addAddress(TUN_IPV6_ADDRESS, TUN_IPV6_PREFIX)
                .addRoute("::", 0)
            Log.i(
                TAG,
                "ipv6 route enabled address=$TUN_IPV6_ADDRESS/$TUN_IPV6_PREFIX serviceConfig=${config.enableIPv6}",
            )
        } else {
            Log.i(TAG, "ipv6 route disabled by effective config serviceConfig=${config.enableIPv6}")
        }

        Log.i(
            TAG,
            "own package remains inside vpn route; core outbound sockets are protected individually",
        )

        tunPfd = builder.establish() ?: error("VpnService.Builder.establish returned null")
        val fd = tunPfd!!.detachFd()
        tunPfd = null
        Log.i(TAG, "tun established fd=$fd")
        return fd
    }

    private fun resolveEffectiveIPv6(config: PreparedVpnConfig): Boolean {
        return try {
            val enabled = Clashmicore.effectiveIPv6(
                config.corePath,
                config.corePathPatch,
                config.corePathPatchFinal,
            )
            if (enabled != config.enableIPv6) {
                Log.i(
                    TAG,
                    "ipv6 route config differs from service.json effective=$enabled serviceConfig=${config.enableIPv6}",
                )
            }
            enabled
        } catch (error: Throwable) {
            Log.w(
                TAG,
                "resolve effective ipv6 failed; fallback serviceConfig=${config.enableIPv6}: ${error.message}",
                error,
            )
            config.enableIPv6
        }
    }

    private fun installSocketProtector() {
        Clashmicore.setSocketProtector(
            object : SocketProtector {
                override fun protect(fd: Long): Boolean = protectCoreSocket(fd)
            },
        )
        Log.i(TAG, "socket protector installed")
    }

    private fun protectCoreSocket(fd: Long): Boolean {
        if (fd < 0 || fd > Int.MAX_VALUE) {
            Log.w(TAG, "socket protect rejected invalid fd=$fd")
            return false
        }
        val ok = protect(fd.toInt())
        if (!ok) {
            Log.w(TAG, "VpnService.protect returned false fd=$fd")
        }
        return ok
    }

    private fun registerNetworkCallback() {
        if (networkCallback != null) {
            return
        }
        val connectivityManager = getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                updateAndroidNetworkInfo("network available")
            }

            override fun onLost(network: Network) {
                updateAndroidNetworkInfo("network lost")
            }

            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                updateAndroidNetworkInfo("link properties changed")
            }

            override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                updateAndroidNetworkInfo("network capabilities changed")
            }
        }
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        try {
            connectivityManager.registerNetworkCallback(request, callback)
            networkCallback = callback
            Log.i(TAG, "network callback registered")
        } catch (error: Throwable) {
            Log.w(TAG, "register network callback failed: ${error.message}", error)
        }
    }

    private fun unregisterNetworkCallback() {
        val callback = networkCallback ?: return
        networkCallback = null
        try {
            getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(callback)
            Log.i(TAG, "network callback unregistered")
        } catch (error: Throwable) {
            Log.w(TAG, "unregister network callback ignored: ${error.message}")
        }
    }

    private fun updateAndroidNetworkInfo(reason: String) {
        try {
            val snapshot = buildAndroidNetworkSnapshot(reason) ?: return
            Clashmicore.setAndroidNetworkInfo(snapshot.json.toString())
            Log.i(
                TAG,
                "android network info sent reason=$reason default=${snapshot.defaultInterface} interfaces=${snapshot.interfaceCount}",
            )
        } catch (error: Throwable) {
            Log.w(TAG, "send android network info failed reason=$reason error=${error.message}", error)
        }
    }

    private fun buildAndroidNetworkSnapshot(reason: String): AndroidNetworkSnapshot? {
        val connectivityManager = getSystemService(ConnectivityManager::class.java)
        val activeNetwork = connectivityManager.activeNetwork
        val candidates = connectivityManager.allNetworks.mapNotNull { network ->
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return@mapNotNull null
            val linkProperties = connectivityManager.getLinkProperties(network) ?: return@mapNotNull null
            val interfaceName = linkProperties.interfaceName?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                return@mapNotNull null
            }
            if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                return@mapNotNull null
            }
            val addresses = JSONArray()
            linkProperties.linkAddresses.forEach { address ->
                addresses.put(address.toString())
            }
            if (addresses.length() == 0) {
                return@mapNotNull null
            }
            val dnsServers = JSONArray()
            linkProperties.dnsServers.forEach { server ->
                dnsServers.put(server.hostAddress)
            }
            val payload = JSONObject()
                .put("name", interfaceName)
                .put("index", interfaceIndex(interfaceName))
                .put("mtu", linkProperties.mtu)
                .put("addresses", addresses)
                .put("dnsServers", dnsServers)
            AndroidNetworkCandidate(
                name = interfaceName,
                payload = payload,
                isActive = network == activeNetwork,
                isValidated = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
            )
        }
        if (candidates.isEmpty()) {
            Log.w(TAG, "no non-vpn internet network info available reason=$reason")
            val payload = JSONObject()
                .put("defaultInterface", "")
                .put("interfaces", JSONArray())
            return AndroidNetworkSnapshot(payload, "", 0)
        }
        val default = candidates.firstOrNull { it.isActive && it.isValidated }
            ?: candidates.firstOrNull { it.isActive }
            ?: candidates.firstOrNull { it.isValidated }
            ?: candidates.first()
        val interfaces = JSONArray()
        candidates.forEach { interfaces.put(it.payload) }
        val payload = JSONObject()
            .put("defaultInterface", default.name)
            .put("interfaces", interfaces)
        return AndroidNetworkSnapshot(payload, default.name, candidates.size)
    }

    private fun interfaceIndex(name: String): Int = runCatching {
        NetworkInterface.getByName(name)?.index ?: 0
    }.getOrElse {
        Log.w(TAG, "lookup interface index failed name=$name error=${it.message}")
        0
    }

    private fun closeTunFd() {
        val fd = tunFd
        tunFd = -1
        if (fd >= 0) {
            try {
                ParcelFileDescriptor.adoptFd(fd).close()
                Log.i(TAG, "tun fd closed fd=$fd")
            } catch (error: Throwable) {
                Log.w(TAG, "close tun fd ignored: ${error.message}")
            }
        }
        try {
            tunPfd?.close()
        } catch (error: Throwable) {
            Log.w(TAG, "close tun pfd ignored: ${error.message}")
        } finally {
            tunPfd = null
        }
    }

    private fun failStart(message: String) {
        Log.e(TAG, message)
        updateState("disconnected")
        VpnServiceRuntime.completeStart(VpnServiceRuntime.errorResult(message))
        stopSelf()
    }

    private fun updateState(state: String, params: Map<String, String> = emptyMap()) {
        VpnServiceRuntime.updateState(state, params)
        val intent = Intent(ACTION_STATE)
            .setPackage(packageName)
            .putExtra(EXTRA_STATE, state)
        params.forEach { (key, value) -> intent.putExtra(key, value) }
        sendBroadcast(intent)
        if (state == "connected") {
            sendBroadcast(Intent(ACTION_START_RESULT).setPackage(packageName))
        } else if (state == "disconnected") {
            sendBroadcast(Intent(ACTION_STOPED).setPackage(packageName))
        }
        Log.i(TAG, "state broadcast state=$state")
    }

    private fun restorePreparedConfig(): PreparedVpnConfig? {
        val configFile = File(filesDir, SERVICE_CONFIG_FILE_NAME)
        return runCatching {
            PreparedVpnConfig.fromConfigFile(configFile)?.also {
                VpnServiceRuntime.setPreparedConfig(it)
                Log.i(TAG, "prepared config restored from ${configFile.absolutePath}")
            }
        }.getOrElse {
            Log.w(TAG, "restore prepared config failed path=${configFile.absolutePath}: ${it.message}", it)
            null
        }
    }

    private fun startForegroundService() {
        createNotificationChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel = NotificationChannel(CHANNEL_ID, "MoneyFly VPN", NotificationManager.IMPORTANCE_LOW)
        channel.setShowBadge(false)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else {
            null
        }
        val icon = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.stat_sys_download_done
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(icon)
            .setContentTitle("MoneyFly")
            .setContentText("VPN is running")
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun clearErrorFile(config: PreparedVpnConfig) {
        if (config.errorPath.isNotEmpty()) {
            runCatching { File(config.errorPath).delete() }
        }
    }

    private fun writeErrorFile(config: PreparedVpnConfig?, message: String) {
        val errorPath = config?.errorPath.orEmpty()
        if (errorPath.isEmpty()) {
            return
        }
        runCatching {
            File(errorPath).writeText(message)
        }.onFailure {
            Log.w(TAG, "write error file failed: ${it.message}")
        }
    }

    companion object {
        const val ACTION_START = "io.nebula.vpn_service.START"
        const val ACTION_STOP = "io.nebula.vpn_service.STOP"
        const val ACTION_STATE_CHANGED = "io.nebula.vpn_service.STATE_CHANGED"
        const val ACTION_START_RESULT = "io.nebula.vpn_service.START_RESULT"
        const val ACTION_STOPED = "io.nebula.vpn_service.STOPED"
        const val ACTION_STATE = ACTION_STATE_CHANGED
        const val EXTRA_STATE = "state"
        const val service_file_name = "service.json"
        const val profile_file_name = "profile.json"
        private const val TAG = "VpnServiceImpl"
        private const val SERVICE_CONFIG_FILE_NAME = "service.json"
        private const val CHANNEL_ID = "clashmi_vpn"
        private const val NOTIFICATION_ID = 6210
        private const val DEFAULT_MTU = 4064
        private const val TUN_IPV4_ADDRESS = "172.19.0.1"
        private const val TUN_IPV4_PREFIX = 30
        private const val TUN_IPV6_ADDRESS = "fdfe:dcbe:9876::1"
        private const val TUN_IPV6_PREFIX = 126
        private const val TUN_DNS_SERVER = "172.19.0.2"

        @JvmStatic
        fun getCurrentState(): VpnState {
            return when (VpnServiceRuntime.currentState) {
                "connected" -> VpnState.CONNECTED
                "connecting" -> VpnState.CONNECTING
                "disconnecting" -> VpnState.DISCONNECTING
                "reasserting" -> VpnState.REASSERTING
                else -> VpnState.DISCONNECTED
            }
        }
    }

    private data class AndroidNetworkCandidate(
        val name: String,
        val payload: JSONObject,
        val isActive: Boolean,
        val isValidated: Boolean,
    )

    private data class AndroidNetworkSnapshot(
        val json: JSONObject,
        val defaultInterface: String,
        val interfaceCount: Int,
    )
}
