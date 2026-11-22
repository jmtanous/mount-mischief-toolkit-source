package org.mountmischief.mount_mischief_toolkit

import android.app.Activity
import android.view.WindowManager
import io.flutter.plugins.urllauncher.WebViewActivity
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = ToolkitApplication::class)
class PilotScreenAwakeTest {
    private fun awake(activity: Activity) =
        activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0

    @Test fun pilotHonorsSavedPreferenceAcrossPauseResumeAndRecreation() {
        val main = Robolectric.buildActivity(Activity::class.java).setup().get()
        val setting = ScreenAwake(main)
        setting.enabled = true
        val browser = Robolectric.buildActivity(WebViewActivity::class.java).setup()
        assertTrue(awake(browser.get()))
        browser.pause()
        assertFalse(awake(browser.get()))
        browser.resume()
        assertTrue(awake(browser.get()))
        browser.pause().stop().destroy()
        val recreated = Robolectric.buildActivity(WebViewActivity::class.java).setup()
        assertTrue(awake(recreated.get()))
        recreated.pause()
        setting.enabled = false
        recreated.resume()
        assertFalse(awake(recreated.get()))
        recreated.pause().stop().destroy()
    }

    @Test fun temporaryToolkitOperationDoesNotForcePilotOrOtherWindowsAwake() {
        val main = Robolectric.buildActivity(Activity::class.java).setup().get()
        val setting = ScreenAwake(main)
        setting.enabled = false
        setting.operation = true
        setting.foreground = true
        assertTrue(awake(main))
        val browser = Robolectric.buildActivity(WebViewActivity::class.java).setup()
        assertFalse(awake(browser.get()))
        setting.enabled = true
        val unrelated = Robolectric.buildActivity(Activity::class.java).setup().get()
        assertFalse(awake(unrelated))
        browser.pause().stop().destroy()
        setting.enabled = false
    }
}
