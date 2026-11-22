package org.mountmischief.mount_mischief_toolkit

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import java.io.ByteArrayInputStream
import java.io.FilterInputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL

/** Only public map/lookup GETs leave the mount's Wi-Fi-bound process. */
internal class PilotInternet(context: Context, private val pilotOrigin: String, private val unavailable: () -> Unit) {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)

    companion object {
        fun publicHeaders(headers: Map<String, String>) = headers.filterKeys {
            it.lowercase() in setOf("origin", "accept", "accept-language")
        }
        fun responseHeaders(headers: Map<String, String>, requestOrigin: String?, pilotOrigin: String): Map<String, String> {
            if (requestOrigin != pilotOrigin) return headers
            // Public lookup responses may be cached without Vary: Origin. This
            // credential-free native adapter exposes them only to the paired Pilot.
            return headers.filterKeys { it.lowercase() != "access-control-allow-origin" } +
                ("Access-Control-Allow-Origin" to pilotOrigin)
        }
        fun allowed(url: String, method: String): Boolean = runCatching {
            val uri = URI(url)
            uri.scheme == "https" && uri.userInfo == null && uri.port in listOf(-1, 443) &&
                method in listOf("GET", "HEAD") && uri.host in setOf(
                    "tile.openstreetmap.org", "a.tile.openstreetmap.org",
                    "b.tile.openstreetmap.org", "c.tile.openstreetmap.org",
                    "nominatim.openstreetmap.org", "api.open-meteo.com"
                )
        }.getOrDefault(false)

        fun failed() = WebResourceResponse("text/plain", "UTF-8", 503, "Unavailable",
            mapOf("Access-Control-Allow-Origin" to "*"),
            ByteArrayInputStream("Map or location lookup unavailable. Check mobile data.".toByteArray()))
    }

    fun load(request: WebResourceRequest): WebResourceResponse {
        if (!allowed(request.url.toString(), request.method)) return failed()
        var connection: HttpURLConnection? = null
        return try {
            val network = connectivity.allNetworks.firstOrNull {
                val caps = connectivity.getNetworkCapabilities(it)
                caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            } ?: throw IllegalStateException("No internet network")
            connection = network.openConnection(URL(request.url.toString())) as HttpURLConnection
            val http = connection
            http.connectTimeout = 8000
            http.readTimeout = 10000
            http.instanceFollowRedirects = false
            http.requestMethod = request.method
            http.setRequestProperty("User-Agent", "MountMischiefToolkit/0.1 (Pilot map viewer)")
            http.setRequestProperty("Accept-Encoding", "identity")
            // These services emit CORS response headers only for an Origin request.
            // Preserve browser semantics without forwarding cookies or credentials.
            publicHeaders(request.requestHeaders).forEach { (name, value) ->
                http.setRequestProperty(name, value)
            }
            val status = http.responseCode
            if (status !in 200..299) throw IllegalStateException("Lookup HTTP $status")
            val headers = responseHeaders(http.headerFields.filterKeys { it != null }
                .mapValues { it.value.joinToString(", ") },
                request.requestHeaders.entries.firstOrNull { it.key.equals("origin", true) }?.value, pilotOrigin)
            val stream = object : FilterInputStream(http.inputStream) {
                override fun close() { try { super.close() } finally { http.disconnect() } }
            }
            WebResourceResponse(http.contentType?.substringBefore(';') ?: "application/octet-stream",
                "UTF-8", status, http.responseMessage ?: "OK", headers, stream)
        } catch (_: Exception) {
            connection?.disconnect()
            unavailable()
            failed()
        }
    }
}
