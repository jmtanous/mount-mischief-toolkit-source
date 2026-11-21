package org.mountmischief.mount_mischief_toolkit

import android.app.Activity
import android.view.WindowManager
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class ScreenAwakeTest {
    @Test fun preferenceSurvivesOperationsAndRecreationButOnlyAppliesInForeground() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val awake = ScreenAwake(activity)
        fun isAwake() = activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0
        awake.foreground = true
        assertFalse(isAwake())
        awake.enabled = true
        assertTrue(isAwake())
        awake.operation = true
        awake.operation = false
        assertTrue(isAwake())
        awake.foreground = false
        assertFalse(isAwake())
        awake.foreground = true
        assertTrue(isAwake())
        val restored = ScreenAwake(activity)
        assertTrue(restored.enabled)
        restored.foreground = true
        restored.enabled = false
        assertFalse(isAwake())
        restored.operation = true
        assertTrue(isAwake())
        restored.foreground = false
        assertFalse(isAwake())
        restored.operation = false
        restored.foreground = true
        assertFalse(isAwake())
    }
}
