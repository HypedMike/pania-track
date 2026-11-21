package app.pania.trailrecorder

import android.Manifest
import android.app.Activity
import android.content.Intent
import androidx.core.content.ContextCompat
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.Permission
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSArray
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin

@InvokeArg
class StartOptions {
    var intervalMs: Long = 5_000
}

@TauriPlugin(
    permissions = [
        // Needed on Android 13+ to show the recording notification. Recording works without it,
        // but the user would not see that it is running.
        Permission(strings = [Manifest.permission.POST_NOTIFICATIONS], alias = "notifications"),
    ],
)
class TrailRecorderPlugin(private val activity: Activity) : Plugin(activity) {
    private val context get() = activity.applicationContext

    @Command
    fun start(invoke: Invoke) {
        val options = invoke.parseArgs(StartOptions::class.java)
        PointBuffer.lastError = null
        val intent = Intent(context, RecorderService::class.java)
            .putExtra(RecorderService.EXTRA_INTERVAL_MS, options.intervalMs)
        try {
            ContextCompat.startForegroundService(context, intent)
            invoke.resolve()
        } catch (e: Exception) {
            invoke.reject("Could not start recording: ${e.message}")
        }
    }

    @Command
    fun stop(invoke: Invoke) {
        context.stopService(Intent(context, RecorderService::class.java))
        PointBuffer.running = false
        invoke.resolve()
    }

    @Command
    fun takePoints(invoke: Invoke) {
        val points = JSArray()
        for (p in PointBuffer.take(context)) points.put(p.toJson())
        val result = JSObject()
        result.put("points", points)
        result.put("running", PointBuffer.running)
        result.put("error", PointBuffer.lastError)
        invoke.resolve(result)
    }
}
