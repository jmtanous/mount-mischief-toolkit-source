package org.mountmischief.mount_mischief_toolkit

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.ActivityNotFoundException
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.webkit.*
import android.widget.Toast
import java.net.URI
import org.json.JSONObject

/** Local Pilot browser: mount sockets stay on Wi-Fi; public maps use validated internet. */
class PilotActivity : Activity() {
    private lateinit var browser: WebView
    private lateinit var origin: String
    private val handler = Handler(Looper.getMainLooper())
    private var pendingLocation: Int? = null
    private var listener: LocationListener? = null
    private var lastNetworkNotice = 0L
    private val timeout = Runnable { locationError("No GPS fix yet. Try outdoors or enter coordinates manually.", 3) }
    private val locationManager by lazy { getSystemService(LocationManager::class.java) }

    companion object {
        const val LOCATION_REQUEST = 824
        fun originOf(url: String): String? = runCatching {
            val uri = URI(url)
            require(uri.scheme == "http" && !uri.host.isNullOrEmpty() &&
                uri.port == 8081 && uri.userInfo == null)
            "http://${uri.host}:8081"
        }.getOrNull()
    }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val url = intent.getStringExtra("url") ?: run { finish(); return }
        origin = originOf(url) ?: run { finish(); return }
        browser = WebView(this)
        setContentView(browser)
        browser.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            setSupportMultipleWindows(false)
        }
        val internet = PilotInternet(this, origin) {
            runOnUiThread {
                if (System.currentTimeMillis() - lastNetworkNotice > 15000) {
                    lastNetworkNotice = System.currentTimeMillis()
                    notice("Maps and site lookups need mobile data or internet. Manual coordinates still work.")
                }
            }
        }
        browser.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (originOf(request.url.toString()) == origin) return false
                // User-selected documentation/weather links open outside the GPS-enabled browser.
                if (request.isForMainFrame && request.hasGesture() && request.url.scheme == "https") {
                    try { startActivity(Intent(Intent.ACTION_VIEW, request.url)) }
                    catch (_: ActivityNotFoundException) { notice("No browser is available to open this link.") }
                }
                return true
            }

            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                val url = request.url.toString()
                if (originOf(url) == origin) return null
                // Never substitute IP geolocation for the phone's GPS: it can pick a different city.
                return if (PilotInternet.allowed(url, request.method)) internet.load(request)
                    else PilotInternet.failed()
            }

            override fun onPageStarted(view: WebView, url: String, icon: android.graphics.Bitmap?) {
                cancelLocation()
            }

            override fun onPageFinished(view: WebView, url: String) {
                if (originOf(url) == origin) view.evaluateJavascript(locationScript, null)
            }
        }
        browser.webChromeClient = object : WebChromeClient() {
            override fun onJsPrompt(view: WebView, url: String, message: String,
                defaultValue: String?, result: JsPromptResult): Boolean {
                if (message != "MMT_PHONE_LOCATION") return false
                val id = defaultValue?.toIntOrNull()
                result.confirm("")
                if (originOf(url) == origin && originOf(view.url ?: "") == origin && id != null && id > 0) {
                    if (pendingLocation != null) locationError("A location request is already running.", 2)
                    pendingLocation = id
                    if (hasLocationPermission()) locate()
                    else requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION), LOCATION_REQUEST)
                }
                return true
            }
        }
        if (state == null || browser.restoreState(state) == null) browser.loadUrl(url)
    }

    private fun hasLocationPermission() =
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        if (code == LOCATION_REQUEST && pendingLocation != null) {
            if (hasLocationPermission()) locate()
            else locationError("Location permission denied. Enter coordinates manually.", 1)
        }
    }

    private fun locate() {
        notice("Getting phone location…")
        val fix = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                val id = pendingLocation ?: return
                // Accept a fresh fix, never a stale cached observing site.
                if ((android.os.SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1e9 > 30) return
                val coords = JSONObject().put("latitude", location.latitude).put("longitude", location.longitude)
                    .put("accuracy", location.accuracy.toDouble())
                    .put("altitude", if (location.hasAltitude()) location.altitude else JSONObject.NULL)
                    .put("altitudeAccuracy", JSONObject.NULL).put("heading", JSONObject.NULL).put("speed", JSONObject.NULL)
                val position = JSONObject().put("coords", coords).put("timestamp", location.time)
                cancelLocation()
                deliver(id, position.toString(), "null")
            }
        }
        listener = fix
        try {
            val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
                .filter { locationManager.isProviderEnabled(it) }
            if (providers.isEmpty()) { locationError("Turn on Android Location or enter coordinates manually.", 2); return }
            handler.postDelayed(timeout, 20000)
            providers.forEach { locationManager.requestLocationUpdates(it, 0L, 0f, fix, Looper.getMainLooper()) }
        } catch (_: SecurityException) { locationError("Location permission denied. Enter coordinates manually.", 1) }
    }

    private fun deliver(id: Int, position: String, error: String) {
        if (!isFinishing && originOf(browser.url ?: "") == origin)
            browser.evaluateJavascript("window.__mmtLocationResult?.($id,$position,$error)", null)
    }

    private fun locationError(message: String, code: Int) {
        val id = pendingLocation ?: return
        cancelLocation()
        notice(message)
        deliver(id, "null", JSONObject().put("code", code).put("message", message).toString())
    }

    private fun cancelLocation() {
        handler.removeCallbacks(timeout)
        listener?.let { locationManager.removeUpdates(it) }
        listener = null
        pendingLocation = null
    }
    private fun notice(message: String) = Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    override fun onStop() { locationError("Location request cancelled. Tap LOCATE to try again.", 2); super.onStop() }
    override fun onSaveInstanceState(state: Bundle) { browser.saveState(state); super.onSaveInstanceState(state) }
    override fun onDestroy() { cancelLocation(); if (::browser.isInitialized) browser.destroy(); super.onDestroy() }
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() { if (browser.canGoBack()) browser.goBack() else super.onBackPressed() }

    private val locationScript = """
        (() => {
          if (window.__mmtLocationResult) return;
          let serial = 0;
          const pending = new Map();
          window.__mmtLocationResult = (id, position, error) => {
            const request = pending.get(id); if (!request) return;
            pending.delete(id);
            if (error) { if (request.error) request.error(error); }
            else request.success(position);
          };
          const getCurrentPosition = (success, error) => {
            const id = ++serial; pending.set(id, {success, error});
            window.prompt('MMT_PHONE_LOCATION', String(id));
          };
          Object.defineProperty(navigator.geolocation, 'getCurrentPosition', {value:getCurrentPosition, configurable:true});
        })();
    """.trimIndent()
}
