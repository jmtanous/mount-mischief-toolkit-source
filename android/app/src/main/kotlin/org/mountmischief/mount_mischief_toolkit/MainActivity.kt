package org.mountmischief.mount_mischief_toolkit

import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val wifiStatus by lazy { WifiStatus(this) }
    private val screenAwake by lazy { ScreenAwake(this) }
    override fun onResume() { super.onResume(); screenAwake.foreground = true; wifiStatus.resume() }
    override fun onPause() { screenAwake.foreground = false; wifiStatus.pause(); super.onPause() }
    private val bluetoothWake by lazy { BluetoothWake(this) }
    override fun onStop() { bluetoothWake.background(); super.onStop() }
    override fun onDestroy() { bluetoothWake.cancel(); super.onDestroy() }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == BluetoothWake.PERMISSION_REQUEST) bluetoothWake.permissionsResult(grantResults)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "org.mountmischief/wifi-status").setStreamHandler(wifiStatus)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.mountmischief/toolkit")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openPilot" -> {
                        val url = call.argument<String>("url")
                        if (url == null || PilotActivity.originOf(url) == null)
                            result.error("INVALID_URL", "Invalid Pilot address", null)
                        else {
                            startActivity(Intent(this, PilotActivity::class.java).putExtra("url", url))
                            result.success(null)
                        }
                    }
                    "wifiStatus" -> result.success(wifiStatus.read())
                    "bluetoothScan" -> bluetoothWake.scan(result)
                    "bluetoothWake" -> bluetoothWake.wake(call.argument<String>("address"), result)
                    "bluetoothCancel" -> { bluetoothWake.cancel(); result.success(null) }
                    "bluetoothSettings" -> { startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)); result.success(null) }
                    "appSettings" -> { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:$packageName"))); result.success(null) }
                    "wifiSettings" -> { startActivity(Intent(Settings.ACTION_WIFI_SETTINGS)); result.success(null) }
                    "keepAwake" -> {
                        screenAwake.operation = call.arguments == true
                        result.success(null)
                    }
                    "getKeepScreenAwake" -> result.success(screenAwake.enabled)
                    "setKeepScreenAwake" -> {
                        screenAwake.enabled = call.arguments == true
                        result.success(null)
                    }
                    "bindWifi" -> {
                        val manager = getSystemService(ConnectivityManager::class.java)
                        val network = manager.allNetworks.firstOrNull {
                            manager.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                        }
                        if (network == null || !manager.bindProcessToNetwork(network))
                            result.error("NO_WIFI", "Join the device Wi-Fi in Android settings first.", null)
                        else result.success(null)
                    }
                    "releaseNetwork" -> {
                        getSystemService(ConnectivityManager::class.java).bindProcessToNetwork(null)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
