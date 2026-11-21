package org.mountmischief.mount_mischief_toolkit

import android.app.Activity
import android.content.Context
import android.view.WindowManager

/** User preference and temporary operation requests share a foreground-only flag. */
class ScreenAwake(private val activity: Activity) {
    private val preferences = activity.getSharedPreferences("screen_awake", Context.MODE_PRIVATE)
    var enabled: Boolean
        get() = preferences.getBoolean("enabled", false)
        set(value) { preferences.edit().putBoolean("enabled", value).apply(); update() }
    var operation = false
        set(value) { field = value; update() }
    var foreground = false
        set(value) { field = value; update() }
    private fun update() {
        if (foreground && (enabled || operation))
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
