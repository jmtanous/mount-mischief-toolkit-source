package org.mountmischief.mount_mischief_toolkit

import android.app.Activity
import android.view.View
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat

/** Resize the browser viewport, including fixed-position web controls, above system UI. */
internal object PilotBrowserInsets {
    fun apply(activity: Activity) {
        WindowCompat.setDecorFitsSystemWindows(activity.window, false)
        val content = activity.findViewById<View>(android.R.id.content)
        ViewCompat.setOnApplyWindowInsetsListener(content) { view, insets ->
            val safe = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or
                    WindowInsetsCompat.Type.displayCutout() or
                    WindowInsetsCompat.Type.ime()
            )
            // Absolute padding: repeated dispatch and activity resume must not accumulate it.
            view.setPadding(safe.left, safe.top, safe.right, safe.bottom)
            WindowInsetsCompat.CONSUMED
        }
        ViewCompat.requestApplyInsets(content)
    }
}
