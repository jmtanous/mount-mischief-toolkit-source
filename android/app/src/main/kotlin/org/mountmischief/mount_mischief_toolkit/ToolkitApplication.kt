package org.mountmischief.mount_mischief_toolkit

import android.app.Activity
import android.app.Application
import android.os.Bundle

/** Apply the saved screen preference to url_launcher's separate Pilot window. */
class ToolkitApplication : Application(), Application.ActivityLifecycleCallbacks {
    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(this)
    }

    private fun isPilotBrowser(activity: Activity) =
        activity.javaClass.name == "io.flutter.plugins.urllauncher.WebViewActivity"

    override fun onActivityResumed(activity: Activity) {
        if (isPilotBrowser(activity)) ScreenAwake(activity).foreground = true
    }

    override fun onActivityPaused(activity: Activity) {
        if (isPilotBrowser(activity)) ScreenAwake(activity).foreground = false
    }

    override fun onActivityCreated(activity: Activity, state: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
}
