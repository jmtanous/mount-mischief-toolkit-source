package org.mountmischief.mount_mischief_toolkit

import android.Manifest
import android.content.Intent
import android.content.pm.ActivityInfo
import android.webkit.WebView
import android.view.ViewGroup
import android.view.WindowManager
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = ToolkitApplication::class)
class PilotActivityTest {
    @Test fun cachedPublicLookupIsExposedOnlyToThePairedPilotOrigin() {
        val origin = "http://192.168.0.1:8081"
        val headers = mapOf("Content-Type" to "application/json")
        assertEquals(origin, PilotInternet.responseHeaders(headers, origin, origin)["Access-Control-Allow-Origin"])
        assertEquals(headers, PilotInternet.responseHeaders(headers, "https://other.test", origin))
        assertEquals(headers, PilotInternet.responseHeaders(headers, null, origin))
    }
    @Test fun lookupPreservesCorsOriginWithoutLeakingCredentials() {
        val headers = PilotInternet.publicHeaders(mapOf(
            "Origin" to "http://192.168.0.1:8081", "Accept" to "application/json",
            "Cookie" to "private", "Authorization" to "private", "X-Private" to "private"))
        assertEquals(mapOf("Origin" to "http://192.168.0.1:8081", "Accept" to "application/json"), headers)
    }
    @Test fun publicRequestsAreLimitedToLookupServicesAndSafeMethods() {
        assertTrue(PilotInternet.allowed("https://a.tile.openstreetmap.org/4/2/1.png", "GET"))
        assertTrue(PilotInternet.allowed("https://tile.openstreetmap.org/0/0/0.png", "HEAD"))
        assertTrue(PilotInternet.allowed("https://api.open-meteo.com/v1/forecast?latitude=0", "GET"))
        for (url in listOf("http://tile.openstreetmap.org/0/0/0.png",
            "https://tile.openstreetmap.org.evil.test/", "https://tile.openstreetmap.org:444/",
            "https://user@tile.openstreetmap.org/", "http://192.168.0.1:8081/config",
            "https://ipapi.co/json/")) assertFalse(url, PilotInternet.allowed(url, "GET"))
        assertFalse(PilotInternet.allowed("https://nominatim.openstreetmap.org/reverse", "POST"))
    }

    @Test fun pilotOriginRejectsOtherPortsSchemesAndCredentials() {
        assertEquals("http://192.168.0.1:8081", PilotActivity.originOf("http://192.168.0.1:8081/config"))
        for (url in listOf("file:///config", "javascript:alert(1)", "http://user@192.168.0.1:8081", "http://192.168.0.1:80"))
            assertNull(PilotActivity.originOf(url))
    }

    @Test fun ownBrowserKeepsAwakeAndHandlesRotationWithoutRecreation() {
        val app = RuntimeEnvironment.getApplication()
        val intent = Intent(app, PilotActivity::class.java).putExtra("url", "http://192.168.0.1:8081")
        val controller = Robolectric.buildActivity(PilotActivity::class.java, intent).setup()
        val activity = controller.get()
        ScreenAwake(activity).enabled = true
        controller.pause().resume()
        assertTrue(activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0)
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        val web = content.getChildAt(0) as WebView
        assertTrue(web.settings.javaScriptEnabled)
        assertFalse(web.settings.allowFileAccess)
        val info = app.packageManager.getActivityInfo(activity.componentName, 0)
        assertTrue(info.configChanges and ActivityInfo.CONFIG_ORIENTATION != 0)
        assertTrue(info.configChanges and ActivityInfo.CONFIG_SCREEN_SIZE != 0)
        activity.onConfigurationChanged(android.content.res.Configuration(activity.resources.configuration).apply {
            orientation = android.content.res.Configuration.ORIENTATION_LANDSCAPE
        })
        assertSame(web, content.getChildAt(0))
        assertEquals("http://192.168.0.1:8081", shadowOf(web).lastLoadedUrl)
        controller.pause()
        assertFalse(activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0)
        controller.stop().destroy()
    }
}
