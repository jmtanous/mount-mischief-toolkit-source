package org.mountmischief.mount_mischief_toolkit

import android.view.View
import android.view.ViewGroup
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.plugins.urllauncher.WebViewActivity
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = ToolkitApplication::class)
class PilotBrowserInsetsTest {
    @Test fun browserViewportExcludesNavigationBarAndUpdatesWithoutAccumulating() {
        val browser = Robolectric.buildActivity(WebViewActivity::class.java).setup()
        val content = browser.get().findViewById<ViewGroup>(android.R.id.content)
        // Robolectric's WebView does not measure a real renderer. Use the same
        // layout parameters with a normal view to check the available viewport.
        val viewport = View(browser.get())
        val params = content.getChildAt(0).layoutParams
        content.removeAllViews()
        content.addView(viewport, params)
        fun dispatch(left: Int, bottom: Int, keyboard: Int = 0) {
            val insets = WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.of(left, 0, 0, bottom))
                .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, keyboard))
                .build()
            ViewCompat.dispatchApplyWindowInsets(content, insets)
            content.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(2410, View.MeasureSpec.EXACTLY))
            content.layout(0, 0, 1080, 2410)
        }
        dispatch(0, 126)
        assertEquals(2284, content.getChildAt(0).bottom)
        browser.pause().stop().start().resume()
        dispatch(0, 126)
        assertEquals(2284, content.getChildAt(0).bottom)
        dispatch(90, 0)
        assertEquals(90, content.getChildAt(0).left)
        assertEquals(2410, content.getChildAt(0).bottom)
        dispatch(0, 126, 800)
        assertEquals(1610, content.getChildAt(0).bottom)
        dispatch(0, 24)
        assertEquals(2386, content.getChildAt(0).bottom)
        browser.pause().stop().destroy()
    }
}
