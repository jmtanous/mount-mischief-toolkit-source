package org.mountmischief.mount_mischief_toolkit

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.content.pm.PackageManager
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.time.Duration
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class BluetoothWakeTest {
    class Reply : MethodChannel.Result {
        var count = 0
        var code: String? = null
        var value: Any? = null
        override fun success(result: Any?) { count++; value = result }
        override fun error(errorCode: String, message: String?, details: Any?) { count++; code = errorCode }
        override fun notImplemented() { throw AssertionError() }
    }
    private lateinit var wake: BluetoothWake
    @Before fun setup() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        shadowOf(activity.application).grantPermissions(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        BluetoothAdapter.getDefaultAdapter().enable()
        wake = BluetoothWake(activity)
    }
    @Test fun scanTimeoutCompletesOnce() {
        val reply = Reply()
        wake.scan(reply)
        assertEquals(0, reply.count)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(13))
        assertEquals(emptyList<Any>(), reply.value)
        wake.cancel()
        assertEquals(1, reply.count)
    }
    @Test fun backgroundCancelsScanAndIgnoresTimeout() {
        val reply = Reply()
        wake.scan(reply)
        wake.background()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(13))
        assertEquals("BLE_CANCELLED", reply.code)
        assertEquals(1, reply.count)
    }
    @Test fun unscannedAddressNeverConnects() {
        val reply = Reply()
        wake.wake("00:11:22:33:44:55", reply)
        assertEquals("BLE_SELECTION", reply.code)
    }
    @Test fun disabledBluetoothGivesActionableError() {
        BluetoothAdapter.getDefaultAdapter().disable()
        val reply = Reply()
        wake.scan(reply)
        assertEquals("BLE_DISABLED", reply.code)
    }
    @Test fun deniedPermissionDoesNotStartScan() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        shadowOf(activity.application).denyPermissions(Manifest.permission.BLUETOOTH_SCAN)
        val helper = BluetoothWake(activity)
        val reply = Reply()
        helper.scan(reply)
        helper.permissionsResult(intArrayOf(PackageManager.PERMISSION_DENIED))
        assertEquals("BLE_PERMISSION", reply.code)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(61))
        assertEquals(1, reply.count)
    }
    @Test fun overlappingRequestDoesNotReplaceActiveScan() {
        val first = Reply()
        val second = Reply()
        wake.scan(first)
        wake.scan(second)
        assertEquals("BLE_BUSY", second.code)
        assertEquals(0, first.count)
        wake.cancel()
        assertEquals("BLE_CANCELLED", first.code)
    }
}
