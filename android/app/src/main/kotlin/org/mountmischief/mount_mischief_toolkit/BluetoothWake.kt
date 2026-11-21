package org.mountmischief.mount_mischief_toolkit

import android.Manifest
import android.app.Activity
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** Foreground-only Polaris discovery and the documented connect/disconnect wake. */
class BluetoothWake(private val activity: Activity) {
    companion object { const val PERMISSION_REQUEST = 7041 }
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var permissionAction: (() -> Unit)? = null
    private var scanner: BluetoothLeScanner? = null
    private var callback: ScanCallback? = null
    private var gatt: BluetoothGatt? = null
    private var generation = 0
    private val found = linkedMapOf<String, BluetoothDevice>()
    private val names = linkedMapOf<String, String>()

    private fun finish(value: Any? = null, code: String? = null, message: String? = null) {
        generation++
        handler.removeCallbacksAndMessages(null)
        permissionAction = null
        try { callback?.let { scanner?.stopScan(it) } } catch (_: SecurityException) {}
        callback = null
        scanner = null
        try { gatt?.disconnect() } catch (_: SecurityException) {}
        try { gatt?.close() } catch (_: SecurityException) {}
        gatt = null
        val result = pending
        pending = null
        if (code == null) result?.success(value) else result?.error(code, message, null)
    }

    fun cancel() { finish(code = "BLE_CANCELLED", message = "Bluetooth wake cancelled.") }
    fun background() { cancel() }

    private fun begin(result: MethodChannel.Result, action: (BluetoothAdapter) -> Unit) {
        if (pending != null) { result.error("BLE_BUSY", "A Bluetooth operation is already active.", null); return }
        pending = result
        val operation = generation
        val run = {
            if (pending != null && generation == operation) {
                try {
                    val adapter = activity.getSystemService(BluetoothManager::class.java)?.adapter
                    if (adapter == null) finish(code = "BLE_UNSUPPORTED", message = "Bluetooth LE is unavailable on this phone.")
                    else if (!adapter.isEnabled) finish(code = "BLE_DISABLED", message = "Turn on Bluetooth in Android settings, then try again.")
                    else action(adapter)
                } catch (_: SecurityException) {
                    finish(code = "BLE_PERMISSION", message = "Allow Nearby devices (or Location on older Android) in app settings, then retry.")
                } catch (e: Exception) {
                    finish(code = "BLE_FAILED", message = "Bluetooth operation failed: ${e.message}")
                }
            }
        }
        val permissions = if (Build.VERSION.SDK_INT >= 31) arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
                          else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        if (permissions.any { activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }) {
            permissionAction = run
            activity.requestPermissions(permissions, PERMISSION_REQUEST)
            handler.postDelayed({ if (operation == generation) finish(code = "BLE_TIMEOUT", message = "Bluetooth permission request timed out. Try again.") }, 60000)
        } else run()
    }

    fun permissionsResult(grants: IntArray) {
        val action = permissionAction ?: return
        permissionAction = null
        handler.removeCallbacksAndMessages(null)
        if (grants.isNotEmpty() && grants.all { it == PackageManager.PERMISSION_GRANTED }) action()
        else finish(code = "BLE_PERMISSION", message = "Bluetooth permission denied. Allow Nearby devices (or Location on older Android) in app settings to scan.")
    }

    fun scan(result: MethodChannel.Result) = begin(result) { adapter ->
        found.clear()
        names.clear()
        val operation = generation
        var received = 0
        var named = 0
        var cachedPolaris = 0
        val cb = object : ScanCallback() {
            override fun onScanResult(type: Int, result: ScanResult) {
                handler.post {
                    if (operation != generation) return@post
                    try {
                        received++
                        if (result.device.name?.startsWith("polaris", ignoreCase = true) == true) cachedPolaris++
                        val name = result.scanRecord?.deviceName ?: return@post
                        named++
                        if (name.startsWith("polaris", ignoreCase = true)) {
                            found[result.device.address] = result.device
                            names[result.device.address] = name
                        }
                    } catch (_: SecurityException) {
                        finish(code = "BLE_PERMISSION", message = "Bluetooth permission was revoked. Allow Nearby devices in app settings.")
                    }
                }
            }
            override fun onScanFailed(errorCode: Int) {
                handler.post { if (operation == generation) finish(code = "BLE_SCAN", message = "Bluetooth scan failed ($errorCode). Wait a moment and retry.") }
            }
        }
        scanner = adapter.bluetoothLeScanner
        if (scanner == null) { finish(code = "BLE_DISABLED", message = "Bluetooth scanner unavailable. Turn Bluetooth on and retry."); return@begin }
        callback = cb
        scanner!!.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), cb)
        handler.postDelayed({
            if (operation == generation) {
                android.util.Log.i("MMTBluetooth", "Scan results=$received named=$named cachedPolaris=$cachedPolaris matched=${names.size}")
                finish(names.map { mapOf("address" to it.key, "name" to it.value) })
            }
        }, 12000)
    }

    fun wake(address: String?, result: MethodChannel.Result) = begin(result) { _ ->
        val device = found[address]
        if (device == null) { finish(code = "BLE_SELECTION", message = "Scan again and select a nearby Polaris."); return@begin }
        val operation = generation
        gatt = device.connectGatt(activity, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(connection: BluetoothGatt, status: Int, state: Int) {
                handler.post {
                    if (operation != generation) { try { connection.close() } catch (_: SecurityException) {}; return@post }
                    if (status != BluetoothGatt.GATT_SUCCESS) finish(code = "BLE_CONNECT", message = "Bluetooth connection failed ($status). Move closer and retry.")
                    else if (state == BluetoothProfile.STATE_CONNECTED) finish(mapOf("connected" to true))
                    else if (state == BluetoothProfile.STATE_DISCONNECTED) finish(code = "BLE_CONNECT", message = "Polaris disconnected before wake completed. Retry nearby.")
                }
            }
        }, BluetoothDevice.TRANSPORT_LE)
        if (gatt == null) finish(code = "BLE_CONNECT", message = "Could not start Bluetooth connection.")
        else handler.postDelayed({ if (operation == generation) finish(code = "BLE_TIMEOUT", message = "Polaris did not answer Bluetooth. Check power and distance, then retry.") }, 12000)
    }
}
