package org.mountmischief.mount_mischief_toolkit

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** Reads current association, including local-only Wi-Fi; never scans or joins. */
class WifiStatus(private val context: Context) : EventChannel.StreamHandler {
    private val handler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var foreground = false
    private var last: Map<String, String>? = null
    private val poll = object : Runnable {
        override fun run() {
            if (!foreground || sink == null) return
            val value = read()
            if (value != last) { last = value; sink?.success(value) }
            handler.postDelayed(this, 2000)
        }
    }
    fun resume() { foreground = true; restart() }
    fun pause() { foreground = false; handler.removeCallbacks(poll) }
    private fun restart() { handler.removeCallbacks(poll); if (foreground && sink != null) handler.post(poll) }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events; last = null; restart() }
    override fun onCancel(arguments: Any?) { sink = null; handler.removeCallbacks(poll) }

    @Suppress("DEPRECATION")
    fun read(): Map<String, String> = try {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val connected = manager.allNetworks.any {
            manager.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
        val info = context.applicationContext.getSystemService(WifiManager::class.java).connectionInfo
        classify(connected, info?.ssid)
    } catch (_: SecurityException) { mapOf("state" to "unknown") }

    companion object {
        fun classify(connected: Boolean, rawSsid: String?): Map<String, String> {
            if (!connected) return mapOf("state" to "disconnected")
            val ssid = rawSsid?.removeSurrounding("\"")
            if (ssid.isNullOrBlank() || ssid == WifiManager.UNKNOWN_SSID)
                return mapOf("state" to "unknown")
            return if (ssid.startsWith("polaris_", ignoreCase = true))
                mapOf("state" to "polaris", "ssid" to ssid)
            else mapOf("state" to "other")
        }
    }
}
